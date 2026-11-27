"""The rack's load history, the input to the load forecast.

Each line of the history file is one reading: ``{"t", "w", "switches"}``.
``bucketed`` turns readings into five-minute means for the models.
"""

import json
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

STEP = timedelta(minutes=5)
EPOCH = datetime(2000, 1, 1, tzinfo=timezone.utc)


@dataclass
class Series:
    """Five-minute buckets ending at the latest reading; ``None`` where nothing was read."""

    start: datetime
    load: list = field(default_factory=list)
    switches: dict = field(default_factory=dict)

    def time(self, i):
        return self.start + i * STEP

    def __len__(self):
        return len(self.load)


def bucket_of(t):
    return EPOCH + ((t - EPOCH) // STEP) * STEP


class History:
    def __init__(self, path):
        self.path = Path(path)

    def append(self, t, watts, switches):
        with open(self.path, "a") as f:
            f.write(
                json.dumps(
                    {"t": t.isoformat(), "w": watts, "switches": switches}
                )
                + "\n"
            )

    def readings(self):
        try:
            with open(self.path) as f:
                return [json.loads(line) for line in f if line.strip()]
        except FileNotFoundError:
            return []

    def bucketed(self, names, since=None):
        sums, last_switch = {}, {}
        for r in self.readings():
            t = datetime.fromisoformat(r["t"])
            if since and t < since:
                continue
            b = bucket_of(t)
            s = sums.setdefault(b, [0.0, 0])
            s[0] += r["w"]
            s[1] += 1
            for name, on in (r.get("switches") or {}).items():
                last_switch.setdefault(name, {})[b] = on
        if not sums:
            return Series(start=bucket_of(datetime.now(timezone.utc)))
        first, last = min(sums), max(sums)
        n = (last - first) // STEP + 1
        series = Series(start=first)
        series.load = [None] * n
        for b, (total, count) in sums.items():
            series.load[(b - first) // STEP] = total / count
        for name in names:
            seen = last_switch.get(name, {})
            series.switches[name] = [
                seen.get(first + i * STEP) for i in range(n)
            ]
        return series


def seed(path, plug_states, device_log, until):
    """Write a history from Home Assistant plug readings before ``until`` and the controller's own log after.

    Plug states are time-weighted into five-minute means; the controller's log already has one reading per cycle.
    """
    points = []
    for s in plug_states:
        try:
            points.append(
                (datetime.fromisoformat(s["last_changed"]), float(s["state"]))
            )
        except ValueError:
            points.append((datetime.fromisoformat(s["last_changed"]), None))
    points.append((until, None))
    sums = {}
    for (t, v), (t_next, _) in zip(points, points[1:]):
        if v is None or t >= until:
            continue
        t_next = min(t_next, until)
        while t < t_next:
            b = bucket_of(t)
            end = min(t_next, b + STEP)
            s = sums.setdefault(b, [0.0, 0.0])
            s[0] += v * (end - t).total_seconds()
            s[1] += (end - t).total_seconds()
            t = end
    rows = [
        {"t": b.isoformat(), "w": total / secs, "switches": {}}
        for b, (total, secs) in sorted(sums.items())
        if secs >= STEP.total_seconds() / 2
    ]
    for line in Path(device_log).read_text().splitlines():
        r = json.loads(line)
        if "snapshot" in r and datetime.fromisoformat(r["t"]) >= until:
            rows.append(
                {"t": r["t"], "w": r["snapshot"]["load_w"], "switches": {}}
            )
    Path(path).write_text("".join(json.dumps(r) + "\n" for r in rows))
    return len(rows)
