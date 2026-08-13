#!/usr/bin/env python3
"""Render a Portal screensaver set from an Apple dynamic-wallpaper HEIC.

An Apple "dynamic desktop" .heic packs every frame of a wallpaper into one
container, plus an XMP `apple_desktop` plist mapping each frame to either a sun
position (solar) or a wall-clock time (h24). These files are huge (>100 MiB) and
the Portals are tiny, so we pre-render each frame to a downscaled JPEG and emit
the frame->sun/time mapping as metadata.json. The Portal then picks a frame for
the current sun elevation without ever fetching the HEIC.

Frames are center-cropped to TARGET_W x TARGET_H: scaled so the shorter axis
fills the target, with the overflow on the longer axis trimmed equally from both
sides. Aspect ratio is preserved (no warping); only the edges are lost.

ImageMagick reads every top-level HEIC image as one sequence, in file order, so
scene N corresponds to apple_desktop image index N. A single decode pass renders
all frames.

Usage: build.py SOURCE.heic OUTDIR
"""

import base64
import json
import os
import plistlib
import re
import subprocess
import sys

TARGET_W = 1280
TARGET_H = 800
JPEG_QUALITY = 88


def render_frames(heic, outdir):
    """Crop every HEIC frame to TARGET_W x TARGET_H; write <index>.jpg.

    Returns the sorted list of frame indices actually written.
    """
    subprocess.run(
        [
            "magick",
            heic,
            "-resize",
            f"{TARGET_W}x{TARGET_H}^",
            "-gravity",
            "center",
            "-extent",
            f"{TARGET_W}x{TARGET_H}",
            "-quality",
            str(JPEG_QUALITY),
            "-interlace",
            "Plane",
            "-strip",
            os.path.join(outdir, "%d.jpg"),
        ],
        check=True,
    )
    indices = sorted(
        int(f[: -len(".jpg")])
        for f in os.listdir(outdir)
        if f.endswith(".jpg") and f[: -len(".jpg")].isdigit()
    )
    if not indices:
        sys.exit("no frames rendered from HEIC")
    return indices


def read_apple_desktop(heic):
    """Return (scheme, plist) from the apple_desktop XMP.

    scheme is "solar", "h24" or "apr" (appearance only); plist is the decoded
    dict. Returns (None, None) when the HEIC carries no such metadata.
    """
    for scheme in ("solar", "h24", "apr"):
        raw = subprocess.run(
            ["exiftool", "-b", "-u", f"-XMP-apple_desktop:{scheme}", heic],
            check=True,
            capture_output=True,
        ).stdout.strip()
        if raw:
            return scheme, plistlib.loads(base64.b64decode(raw))
    return None, None


def appearance_label(index, appearance):
    """light/dark tag for a frame index, from the plist `ap` block (or None)."""
    if not appearance:
        return None
    if index == appearance.get("l"):
        return "light"
    if index == appearance.get("d"):
        return "dark"
    return None


def build_metadata(heic, indices):
    """Assemble the metadata document mapping each frame to its sun/time data."""
    scheme, plist = read_apple_desktop(heic)
    appearance = (plist or {}).get("ap") if plist else None

    # Index the per-frame solar/time entries by their frame index `i`.
    solar = (
        {e["i"]: e for e in (plist or {}).get("si", [])}
        if scheme == "solar"
        else {}
    )
    times = (
        {e["i"]: e for e in (plist or {}).get("ti", [])}
        if scheme == "h24"
        else {}
    )

    frames = []
    for i in indices:
        frame = {"index": i, "file": f"{i}.jpg"}
        label = appearance_label(i, appearance)
        if label:
            frame["appearance"] = label

        if i in solar:
            # apple_desktop solar: `a` is the sun's elevation above the horizon
            # in degrees (negative below), `z` is its azimuth (compass bearing).
            frame["elevation"] = solar[i]["a"]
            frame["azimuth"] = solar[i]["z"]
        elif i in times:
            # apple_desktop h24: `t` is the time as a fraction of the day.
            t = times[i]["t"]
            frame["time"] = t
            minutes = round(t * 24 * 60) % (24 * 60)
            frame["time_of_day"] = f"{minutes // 60:02d}:{minutes % 60:02d}"

        frames.append(frame)

    # Drop the leading Nix store hash from the input path so the recorded
    # source is just the wallpaper filename.
    source = re.sub(r"^[a-z0-9]{32}-", "", os.path.basename(heic))

    meta = {
        "source": source,
        "width": TARGET_W,
        "height": TARGET_H,
        "count": len(frames),
        "scheme": scheme or "static",
        "frames": frames,
    }
    if appearance:
        meta["appearance"] = {
            "light": appearance.get("l"),
            "dark": appearance.get("d"),
        }
    return meta


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        sys.exit("usage: build.py SOURCE.heic OUTDIR")
    heic, outdir = argv
    os.makedirs(outdir, exist_ok=True)

    indices = render_frames(heic, outdir)
    meta = build_metadata(heic, indices)
    with open(os.path.join(outdir, "metadata.json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
