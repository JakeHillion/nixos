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
import datetime
import hashlib
import json
import math
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_HEARTHD = "https://hearthd.neb.jakehillion.me"
# How often we ask the Portal to poll /state, in seconds.
REFRESH_INTERVAL = 10
# hearthd exposes each node's clusters under endpoint 1.
PRIMARY_ENDPOINT = "1"
# The home's location, used to place the sun for the solar wallpaper. This is
# the same hardcoded London fix we use elsewhere; the Portal itself never needs
# coordinates, only the resulting sun position, so it lives here.
PORTAL_LAT = 51.47789474404557
PORTAL_LON = -0.0014709754224478695
# The environment sensors the Portal shows, in display order, mapped from the
# clean slug the template references to hearthd's opaque device id. This mapping
# is the whole point of doing it here: the template only ever sees the slug.
ENVIRONMENT_SENSORS = {
    "bedroom": "sensor.0x00158d00093e8e6d",
    "bathroom": "sensor.0x00158d0009cbf790",
    "living_room": "sensor.0x54ef441000d20037",
    "loft": "sensor.0x54ef441000d20a5a",
}


def template_bytes(path):
    """Read the template file as raw bytes (what we hash and serve verbatim)."""
    with open(path, "rb") as f:
        return f.read()


def template_hash(path):
    """sha256 of the template file, hex — the id the Portal fetches it by."""
    return hashlib.sha256(template_bytes(path)).hexdigest()


def solar_position(lat, lon, when_utc):
    """Where the sun is, as (elevation, azimuth) in degrees, for a UTC instant.

    Elevation is height above the horizon (negative at night); azimuth is
    measured clockwise from true north. This is the NOAA solar-position
    algorithm — accurate to a small fraction of a degree, far finer than the
    16-frame wallpapers it drives — and the geometric (unrefracted) position,
    which is what the frame metadata's elevation/azimuth are keyed to.

    The Portal picks a wallpaper collection for the day and then, frame by
    frame, renders the image whose stored sun position is nearest this one.
    """
    y, mo = when_utc.year, when_utc.month
    day = (
        when_utc.day
        + (when_utc.hour + (when_utc.minute + when_utc.second / 60) / 60) / 24
    )
    if mo <= 2:
        y -= 1
        mo += 12
    a = y // 100
    b = 2 - a + a // 4
    jd = int(365.25 * (y + 4716)) + int(30.6001 * (mo + 1)) + day + b - 1524.5
    t = (jd - 2451545.0) / 36525.0

    rad, deg = math.radians, math.degrees
    mean_long = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360
    mean_anom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
    eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    center = (
        math.sin(rad(mean_anom)) * (1.914602 - t * (0.004817 + 0.000014 * t))
        + math.sin(rad(2 * mean_anom)) * (0.019993 - 0.000101 * t)
        + math.sin(rad(3 * mean_anom)) * 0.000289
    )
    omega = 125.04 - 1934.136 * t
    app_long = mean_long + center - 0.00569 - 0.00478 * math.sin(rad(omega))
    obliquity = (
        23
        + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60)
        / 60
        + 0.00256 * math.cos(rad(omega))
    )
    decl = deg(math.asin(math.sin(rad(obliquity)) * math.sin(rad(app_long))))

    # Equation of time (minutes): the gap between clock noon and true solar noon.
    var_y = math.tan(rad(obliquity / 2)) ** 2
    eot = 4 * deg(
        var_y * math.sin(2 * rad(mean_long))
        - 2 * eccentricity * math.sin(rad(mean_anom))
        + 4
        * eccentricity
        * var_y
        * math.sin(rad(mean_anom))
        * math.cos(2 * rad(mean_long))
        - 0.5 * var_y * var_y * math.sin(4 * rad(mean_long))
        - 1.25 * eccentricity * eccentricity * math.sin(2 * rad(mean_anom))
    )

    minutes = when_utc.hour * 60 + when_utc.minute + when_utc.second / 60
    true_solar_minutes = (minutes + eot + 4 * lon) % 1440
    hour_angle = true_solar_minutes / 4 - 180

    lat_r, decl_r = rad(lat), rad(decl)
    cos_zenith = math.sin(lat_r) * math.sin(decl_r) + math.cos(
        lat_r
    ) * math.cos(decl_r) * math.cos(rad(hour_angle))
    zenith = deg(math.acos(clamp(cos_zenith, -1.0, 1.0)))
    elevation = 90 - zenith

    cos_azimuth = clamp(
        (math.sin(lat_r) * math.cos(rad(zenith)) - math.sin(decl_r))
        / (math.cos(lat_r) * math.sin(rad(zenith))),
        -1.0,
        1.0,
    )
    # acos only spans 0..180; the afternoon (hour angle > 0) is the mirror half.
    azimuth = (
        (deg(math.acos(cos_azimuth)) + 180) % 360
        if hour_angle > 0
        else (540 - deg(math.acos(cos_azimuth))) % 360
    )

    return {"elevation": round(elevation, 4), "azimuth": round(azimuth, 4)}


def clamp(value, low, high):
    """Pin a float into [low, high] — guards acos against tiny FP overshoot."""
    return max(low, min(high, value))


def fetch_hearthd_state(hearthd_url):
    """Fetch hearthd's /v1/state document."""
    with urllib.request.urlopen(f"{hearthd_url}/v1/state", timeout=10) as resp:
        return json.load(resp)


def primary_clusters(node):
    """The clusters on a node's primary endpoint (endpoint 1, else the first)."""
    endpoints = node.get("endpoints", {})
    endpoint = endpoints.get(PRIMARY_ENDPOINT) or next(
        iter(endpoints.values()), {}
    )
    return endpoint.get("clusters", {})


def centi(value):
    """Rescale a hearthd hundredths reading (3020 -> 30.2); keep null as null."""
    return None if value is None else round(value / 100, 1)


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

        clusters = primary_clusters(node)

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


def normalise_environment(hearthd):
    """Map the Portal's named environment sensors to their live readings.

    Keyed by the clean slug from ENVIRONMENT_SENSORS, so the template references
    "environment.bedroom.temperature" and never a device id. hearthd reports
    temperature/humidity in hundredths (3020 -> 30.2 degC, 4150 -> 41.5 %); a
    sensor that's absent or not yet reporting comes through as null.
    """
    by_entity_id = {
        node.get("entity_id", ""): node
        for node in hearthd.get("nodes", {}).values()
    }
    environment = {}
    for slug, entity_id in ENVIRONMENT_SENSORS.items():
        clusters = primary_clusters(by_entity_id.get(entity_id, {}))
        temperature = clusters.get("TemperatureMeasurement") or {}
        humidity = clusters.get("RelativeHumidityMeasurement") or {}
        environment[slug] = {
            "temperature": centi(temperature.get("measured_value")),
            "humidity": centi(humidity.get("measured_value")),
        }
    return environment


def build_state(template_path, hearthd_url):
    """The /state document: template hash, refresh cadence, live state blob."""
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    hearthd = fetch_hearthd_state(hearthd_url)
    return {
        "template": template_hash(template_path),
        "refresh_interval": REFRESH_INTERVAL,
        "state": {
            "lights": normalise_lights(hearthd),
            "environment": normalise_environment(hearthd),
            "sun": solar_position(PORTAL_LAT, PORTAL_LON, now_utc),
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
