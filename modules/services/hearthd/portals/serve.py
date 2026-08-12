#!/usr/bin/env python3
"""Portal dashboard server.

Serves the two endpoints a Portal polls:

  GET /state            -> the live state document: the current template hash,
                           a refresh interval, and the state blob. The light
                           states are pulled live from hearthd on each request;
                           everything else the template needs is baked into the
                           template itself as literals.
  GET /template/<hash>  -> the template body, but only when <hash> matches the
                           sha256 of the file we're serving. The Portal derives
                           this URL from the hash in /state and verifies the body
                           against it, so the two must agree.

The template path is an immutable Nix store path; changing the template is a
redeploy, which restarts this server with the new path. The hash in /state and
the body at /template/<hash> are computed from that file, so they always agree.

Usage:
    serve.py TEMPLATE_PATH [--host HOST] [--port PORT] [--hearthd URL]
"""

import argparse
import hashlib
import json
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_HEARTHD = "https://hearthd.neb.jakehillion.me"
# How often we ask the Portal to poll /state, in seconds.
REFRESH_INTERVAL = 10
# hearthd endpoint 1 is where these lights expose their clusters.
LIGHT_ENDPOINT = "1"


def template_bytes(path):
    """Read the template file as raw bytes (what we hash and serve verbatim)."""
    with open(path, "rb") as f:
        return f.read()


def template_hash(path):
    """sha256 of the template file, hex — the id the Portal fetches it by."""
    return hashlib.sha256(template_bytes(path)).hexdigest()


def fetch_hearthd_state(hearthd_url):
    """Fetch hearthd's /v1/state document."""
    with urllib.request.urlopen(f"{hearthd_url}/v1/state", timeout=10) as resp:
        return json.load(resp)


def normalise_lights(hearthd):
    """Reduce hearthd's node/cluster tree to the flat light map the Portal reads.

    Keyed by entity_id (which is also the command path param, so no second
    lookup is needed). Every switchable light hearthd knows about is published;
    the template picks whichever it references.
    """
    lights = {}
    for node in hearthd.get("nodes", {}).values():
        entity_id = node.get("entity_id", "")
        if not entity_id.startswith("light."):
            continue

        endpoints = node.get("endpoints", {})
        endpoint = endpoints.get(LIGHT_ENDPOINT) or next(
            iter(endpoints.values()), {}
        )
        clusters = endpoint.get("clusters", {})

        on_off = clusters.get("OnOff")
        # Only nodes with an OnOff cluster are switchable lights.
        if on_off is None:
            continue

        level = clusters.get("LevelControl", {}).get("current_level")
        entry = {"on": bool(on_off.get("on_off")), "level": level}

        # Colour: none of these lights expose ColorControl yet, and the hearthd
        # colour read/command shape isn't pinned down. Emit hs only once that's
        # known; until then the Portal treats a light with no hs as non-colour.
        color = clusters.get("ColorControl")
        if color is not None:
            entry["hs"] = (
                None  # TODO: normalise once the ColorControl spec lands
            )

        lights[entity_id] = entry
    return lights


def build_state(template_path, hearthd_url):
    """The /state document: template hash, refresh cadence, live state blob."""
    return {
        "template": template_hash(template_path),
        "refresh_interval": REFRESH_INTERVAL,
        "state": {
            "lights": normalise_lights(fetch_hearthd_state(hearthd_url)),
        },
    }


class Handler(BaseHTTPRequestHandler):
    # Set per-server in main(); shared by all requests.
    template_path = None
    hearthd_url = None

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/state":
            self._handle_state()
        elif self.path.startswith("/template/"):
            self._handle_template(self.path[len("/template/") :])
        else:
            self._send_json(404, {"error": "not found"})

    def _handle_state(self):
        try:
            state = build_state(self.template_path, self.hearthd_url)
        except Exception as e:  # hearthd unreachable, bad template, etc.
            # 5xx makes the Portal back off and keep its last-good screen.
            self._send_json(502, {"error": f"upstream: {e}"})
            return
        self._send_json(200, state)

    def _handle_template(self, requested_hash):
        try:
            body = template_bytes(self.template_path)
        except Exception as e:
            self._send_json(500, {"error": f"template: {e}"})
            return
        actual = hashlib.sha256(body).hexdigest()
        if requested_hash != actual:
            # The requested hash names a template we no longer serve.
            self._send_json(404, {"error": "unknown template hash"})
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # quieter default logging
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Portal dashboard server.")
    parser.add_argument("template", help="path to the template file to serve")
    parser.add_argument("--host", default="0.0.0.0", help="bind address")
    parser.add_argument("--port", type=int, default=8099, help="bind port")
    parser.add_argument(
        "--hearthd", default=DEFAULT_HEARTHD, help="hearthd base URL"
    )
    args = parser.parse_args(argv)

    Handler.template_path = args.template
    Handler.hearthd_url = args.hearthd.rstrip("/")

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(
        f"serving /state and /template/<hash> on {args.host}:{args.port} "
        f"(template={args.template}, hearthd={Handler.hearthd_url})",
        file=sys.stderr,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
