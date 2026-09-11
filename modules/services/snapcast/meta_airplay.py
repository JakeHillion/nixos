#!/usr/bin/env python3
"""Snapcast stream plugin publishing shairport-sync's AirPlay metadata.

shairport-sync writes metadata to a pipe as a stream of XML items, each one a
pair of four-character codes plus base64 data:

    <item><type>73736e63</type><code>PICT</code><length>4</length>
    <data encoding="base64">
    ...
    </data></item>

'core' items carry the tags the sender supplies (album, artist, title); 'ssnc'
items are shairport's own signalling -- play/pause transitions, progress and
cover art. This reads that pipe and republishes it over the stream plugin
protocol, which snapserver speaks over stdin/stdout as newline-delimited
JSON-RPC.
"""

import argparse
import base64
import binascii
import json
import logging
import sys
import threading
import time
import xml.parsers.expat

logger = logging.getLogger("meta_airplay")

# snapserver reads stdout as a single stream of JSON-RPC messages, and both the
# pipe reader and the request handler write to it.
_stdout_lock = threading.Lock()

# 'prgr' timestamps are RTP frame numbers at this rate, wrapping at 2^32.
RTP_RATE = 44100
RTP_WRAP = 2**32


def send(msg):
    """Write one JSON-RPC message to snapserver."""
    with _stdout_lock:
        sys.stdout.write(json.dumps(msg) + "\n")
        sys.stdout.flush()


def art_extension(data):
    """Identify cover art from its magic bytes.

    AirPlay cover art is a JPEG or a PNG with nothing to say which, and
    snapserver serves the bytes back under whatever extension it is given.
    """
    if data.startswith(b"\x89PNG"):
        return "png"
    return "jpg"


class AirplayMetadata:
    """Accumulates pipe items into stream properties and publishes them."""

    def __init__(self, pipe_path):
        self._pipe_path = pipe_path
        self._lock = threading.Lock()

        self._position = 0.0
        self._playback_status = "stopped"
        self._metadata = {}
        self._dirty = False

        self._parser = None
        self._entry = None
        self._buffer = ""

    # -- properties ---------------------------------------------------------

    def properties(self):
        with self._lock:
            return self._properties_locked()

    def _properties_locked(self):
        properties = {
            "playbackStatus": self._playback_status,
            "position": self._position,
        }
        if self._metadata:
            properties["metadata"] = self._metadata
        return properties

    def _publish_locked(self):
        self._dirty = False
        send(
            {
                "jsonrpc": "2.0",
                "method": "Plugin.Stream.Player.Properties",
                "params": self._properties_locked(),
            }
        )

    def _set_metadata(self, key, value):
        if self._metadata.get(key) != value:
            self._metadata[key] = value
            self._dirty = True

    def _clear_metadata(self, key):
        if key in self._metadata:
            del self._metadata[key]
            self._dirty = True

    def _set_playback_status(self, status):
        if self._playback_status != status:
            self._playback_status = status
            self._dirty = True

    # -- pipe parsing -------------------------------------------------------

    def run(self):
        """Read the metadata pipe forever, reopening as senders come and go."""
        while True:
            try:
                # Opening read-only blocks until shairport opens the write end,
                # which is exactly the wait we want.
                with open(self._pipe_path, "rb") as pipe:
                    logger.info("Metadata pipe opened: %s", self._pipe_path)
                    self._start_parser()
                    for line in pipe:
                        self._parse(line)
            except OSError as e:
                logger.error("Error reading metadata pipe, retrying: %s", e)
                time.sleep(5)
                continue

            # EOF: the last sender closed the pipe. Anything still showing as
            # playing never will be again.
            logger.info("Metadata pipe closed")
            with self._lock:
                self._reset_locked()
                self._publish_locked()

    def _start_parser(self):
        self._parser = xml.parsers.expat.ParserCreate("UTF-8")
        self._parser.StartElementHandler = self._element_start
        self._parser.EndElementHandler = self._element_end
        self._parser.CharacterDataHandler = self._character_data
        # The pipe is a bare sequence of <item> elements, so wrap it in a root
        # to keep the parser fed.
        self._parse(b"<metatags>")

    def _parse(self, data):
        try:
            self._parser.Parse(data, False)
        except xml.parsers.expat.ExpatError as e:
            logger.error("Failed to parse metadata, resyncing: %s", e)
            self._start_parser()

    def _element_start(self, name, attrs):
        self._buffer = ""
        if name == "item":
            self._entry = {"length": 0, "data": "", "base64": False}
        if self._entry is not None and "encoding" in attrs:
            self._entry["base64"] = attrs["encoding"] == "base64"

    def _element_end(self, name):
        if self._entry is None:
            return

        if name == "code":
            self._entry["code"] = self._hex_to_str(self._buffer)
        elif name == "type":
            self._entry["type"] = self._hex_to_str(self._buffer)
        elif name == "length":
            self._entry["length"] = int(self._buffer or 0)
        elif name == "data":
            self._entry["data"] = self._buffer
        elif name == "item":
            self._push(self._entry)
            self._entry = None

    def _character_data(self, content):
        self._buffer += content

    @staticmethod
    def _hex_to_str(value):
        """Decode a four-character code from the hex the pipe carries it as."""
        return int(value, 16).to_bytes(4, "big").decode("ascii", "replace")

    # -- item dispatch ------------------------------------------------------

    def _push(self, entry):
        item_type = entry.get("type")
        code = entry.get("code")
        if not item_type or not code:
            return

        with self._lock:
            if item_type == "core":
                # Tags only ever arrive inside an 'mdst'/'mden' bracket.
                self._push_core(code, self._decode(entry))
                publish = False
            elif item_type == "ssnc":
                publish = self._push_shairport(code, entry)
            else:
                return

            # A run of tags is bracketed by 'mdst'/'mden', and cover art
            # separately by 'pcst'/'pcen'. The two interleave unpredictably --
            # a sender may send art before the tags it belongs to, or resend
            # tags it has already sent -- so publish at the end of either.
            if code in ("mden", "pcen"):
                publish = True

            if self._dirty and publish:
                self._publish_locked()

    def _push_core(self, code, data):
        if code == "asal":
            self._set_metadata("album", data)
        elif code == "asar":
            self._set_metadata("artist", [data])
        elif code == "minm":
            self._set_metadata("title", data)
        elif code == "asgn":
            self._set_metadata("genre", [data])
        elif code == "ascp":
            self._set_metadata("composer", [data])

    def _push_shairport(self, code, entry):
        """Handle one shairport item, returning whether to publish now.

        Cover art is half of a bracketed sequence and waits for its 'pcen';
        everything else stands alone and is worth sending as it happens.
        """
        if code == "PICT":
            self._push_cover_art(entry)
            return False

        if code in ("pbeg", "prsm", "pres"):
            self._set_playback_status("playing")
        elif code in ("pfls", "paus"):
            self._set_playback_status("paused")
        elif code == "pend":
            self._reset_locked()
        elif code == "prgr":
            self._push_progress(self._decode(entry))
        return True

    def _push_cover_art(self, entry):
        # A sender with no art for the current track still sends the message,
        # with an empty payload.
        if entry["length"] == 0 or not entry["data"]:
            self._clear_metadata("artData")
            return

        try:
            raw = base64.b64decode(entry["data"])
        except binascii.Error as e:
            logger.error("Failed to decode cover art: %s", e)
            return

        # snapserver's base64 decoder stops at the first character outside the
        # alphabet, and shairport wraps the payload at 76 columns, so hand it
        # back a single unbroken line rather than the form it arrived in.
        self._set_metadata(
            "artData",
            {
                "data": base64.b64encode(raw).decode("ascii"),
                "extension": art_extension(raw),
            },
        )

    def _push_progress(self, data):
        # "rtpstampstart/rtpstampnow/rtpstampend", frame numbers at 44100Hz.
        try:
            start, now, end = (int(field) for field in data.split("/"))
        except ValueError:
            logger.error("Unparseable progress: %r", data)
            return

        self._position = ((now - start) % RTP_WRAP) / RTP_RATE
        self._set_metadata("duration", ((end - start) % RTP_WRAP) / RTP_RATE)
        self._dirty = True

    def _reset_locked(self):
        """Forget the track that just ended, so no client keeps showing it."""
        self._metadata = {}
        self._position = 0.0
        self._playback_status = "stopped"
        self._dirty = True

    @staticmethod
    def _decode(entry):
        if not entry["base64"] or entry["length"] == 0:
            return entry["data"]
        try:
            return base64.b64decode(entry["data"]).decode("utf-8", "replace")
        except binascii.Error as e:
            logger.error("Failed to decode item data: %s", e)
            return ""

    # -- snapserver requests ------------------------------------------------

    def request(self, line):
        try:
            request = json.loads(line)
        except json.JSONDecodeError as e:
            logger.error("Invalid request %r: %s", line, e)
            return

        method = request.get("method", "")
        request_id = request.get("id")

        if method.endswith(".GetProperties"):
            send(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": self.properties(),
                }
            )
        elif request_id is not None:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {
                        "code": -32601,
                        "message": f"{method} is not supported",
                    },
                }
            )


def parse_args():
    parser = argparse.ArgumentParser(
        description="Publishes shairport-sync AirPlay metadata to snapcast."
    )
    parser.add_argument(
        "--metadata-pipe",
        required=True,
        help="Path to shairport-sync's metadata pipe.",
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Debug logging."
    )
    # snapserver passes these to every control script; accept and ignore them.
    parser.add_argument("--stream", help=argparse.SUPPRESS)
    parser.add_argument("--snapcast-host", help=argparse.SUPPRESS)
    parser.add_argument("--snapcast-port", help=argparse.SUPPRESS)
    return parser.parse_args()


def main():
    args = parse_args()

    # stdout is the JSON-RPC channel; snapserver logs whatever arrives on stderr.
    logging.basicConfig(
        stream=sys.stderr,
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    metadata = AirplayMetadata(args.metadata_pipe)
    reader = threading.Thread(
        target=metadata.run, name="AirplayMetadata", daemon=True
    )
    reader.start()

    send({"jsonrpc": "2.0", "method": "Plugin.Stream.Ready"})

    for line in sys.stdin:
        metadata.request(line)


if __name__ == "__main__":
    main()
