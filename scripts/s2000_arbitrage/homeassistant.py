"""Read-only access to Home Assistant sensor states."""

import base64
import json
import os
import socket
import ssl
import struct
import urllib.parse
import urllib.request
from datetime import datetime, timezone


def _get(url, token, path):
    req = urllib.request.Request(
        f"{url}{path}", headers={"Authorization": f"Bearer {token}"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def read(url, token, entity_id):
    """Return ``(state, last_updated)`` for ``entity_id``; state is a float or None if unavailable."""
    body = _get(url, token, f"/api/states/{entity_id}")
    try:
        state = float(body["state"])
    except ValueError:
        state = None
    return state, body.get("last_updated")


def is_on(url, token, entity_id):
    """True or False for an on/off entity, None if it is unavailable."""
    return {"on": True, "off": False}.get(
        _get(url, token, f"/api/states/{entity_id}")["state"]
    )


def attributes(url, token, entity_id):
    """The attributes of ``entity_id``."""
    return _get(url, token, f"/api/states/{entity_id}")["attributes"]


def history(url, token, entity_id, start, end):
    """State changes of ``entity_id`` between ``start`` and ``end``."""
    rows = _get(
        url,
        token,
        f"/api/history/period/{urllib.parse.quote(start.isoformat())}?filter_entity_id={entity_id}"
        f"&minimal_response&no_attributes&end_time={urllib.parse.quote(end.isoformat())}",
    )
    return rows[0] if rows else []


def attribute_history(url, token, entity_id, start, end):
    """``(changed, attributes)`` for each state ``entity_id`` had between ``start`` and ``end``, oldest first."""
    rows = _get(
        url,
        token,
        f"/api/history/period/{urllib.parse.quote(start.isoformat())}?filter_entity_id={entity_id}"
        f"&end_time={urllib.parse.quote(end.isoformat())}",
    )
    return (
        [
            (datetime.fromisoformat(row["last_changed"]), row["attributes"])
            for row in rows[0]
        ]
        if rows
        else []
    )


def hourly_means(url, token, statistic_id, start, end):
    """``(start, end, mean)`` per hour from the recorder's long-term statistics, which outlive its state history."""
    with _Websocket(url) as ws:
        ws.call({"type": "auth", "access_token": token}, expect="auth_ok")
        result = ws.call(
            {
                "id": 1,
                "type": "recorder/statistics_during_period",
                "start_time": start.isoformat(),
                "end_time": end.isoformat(),
                "statistic_ids": [statistic_id],
                "period": "hour",
                "types": ["mean"],
            },
            expect="result",
        )
    t = lambda ms: datetime.fromtimestamp(ms / 1000, timezone.utc)
    return [
        (t(r["start"]), t(r["end"]), r["mean"])
        for r in result["result"].get(statistic_id, [])
        if r["mean"] is not None
    ]


class _Websocket:
    """Just enough of RFC 6455 for request/response JSON over Home Assistant's websocket API."""

    def __init__(self, url):
        u = urllib.parse.urlparse(url)
        tls = u.scheme == "https"
        sock = socket.create_connection(
            (u.hostname, u.port or (443 if tls else 80)), timeout=60
        )
        self.sock = (
            ssl.create_default_context().wrap_socket(
                sock, server_hostname=u.hostname
            )
            if tls
            else sock
        )
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            f"GET {u.path.rstrip('/')}/api/websocket HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode()
        )
        self.buf = b""
        while b"\r\n\r\n" not in self.buf:
            self._fill()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise ConnectionError(head.split(b"\r\n", 1)[0].decode())
        self.call(None, expect="auth_required")

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.sock.close()

    def _fill(self):
        chunk = self.sock.recv(65536)
        if not chunk:
            raise ConnectionError("Home Assistant closed the websocket")
        self.buf += chunk

    def _read(self, n):
        while len(self.buf) < n:
            self._fill()
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _recv(self):
        data = b""
        while True:
            b0, b1 = self._read(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            payload = self._read(n)
            if b0 & 0x0F in (0x0, 0x1):
                data += payload
                if b0 & 0x80:
                    return json.loads(data)

    def _send(self, message):
        payload = json.dumps(message).encode()
        n = len(payload)
        length = (
            bytes([0x80 | n])
            if n < 126
            else (
                bytes([0x80 | 126]) + struct.pack(">H", n)
                if n < 1 << 16
                else bytes([0x80 | 127]) + struct.pack(">Q", n)
            )
        )
        mask = os.urandom(4)
        self.sock.sendall(
            bytes([0x81])
            + length
            + mask
            + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        )

    def call(self, message, expect):
        if message is not None:
            self._send(message)
        reply = self._recv()
        if reply.get("type") != expect or reply.get("success") is False:
            raise ConnectionError(f"Home Assistant replied {reply}")
        return reply
