"""Fit a ``curve.Curve`` from the controller's log.

    curve_fit.py --config FILE [--out battery.json]

With ``[battery] learn = true`` the controller refits daily itself through
``Learner``; this command prints the fit without changing anything.

Each logged cycle carries the device's state (SoC, grid and load watts, mode)
before any command and, when one was sent, after it. Between consecutive cycles
the battery is charging (mode 0, grid above load at both ends) or discharging
(mode 2, no grid at both ends); anything else is skipped. Chains of these form
runs over which the energy in or out is integrated.

SoC is only reported in whole points, so the moment a point boundary was
crossed is placed between the samples either side of it: halfway for one
point, spread evenly for several. The energy between two crossings in one run
is one observation of that point's width.

Each point's width is a weighted mean of observations at that point and its
neighbours, with recent runs weighing more, shrunk towards the configured
constants. How far neighbours reach, how fast old runs fade and how strongly
the constants pull are chosen by leaving each run out in turn and predicting
its widths from the rest. The charger's accepted watts per point are fitted the
same way from the samples taken while charging.
"""

import argparse
import dataclasses
import itertools
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from curve import POINTS, Curve
from loads import REFIT_EVERY

NEIGHBOUR_HALF_POINTS = (0, 1, 2, 4, 8, 16)
AGE_HALF_LIFE_DAYS = (3, 10, 30, None)
PRIOR_WEIGHT = (0.5, 1, 2, 4, 8, 16)


@dataclass(frozen=True)
class Sample:
    t: datetime
    soc: int
    mode: int
    grid_w: float
    load_w: float

    @property
    def charge_w(self):
        return self.grid_w - self.load_w


@dataclass(frozen=True)
class Obs:
    point: int
    value: float
    run: int
    t: datetime


def samples(path):
    """Device states in time order: each cycle's state before, then after any command."""
    out = []
    for line in open(path):
        r = json.loads(line)
        t = datetime.fromisoformat(r["t"])
        before = r.get("battery") or r.get("snapshot")
        after = (r.get("applied") or {}).get("after") or r.get("after")
        for s in (before, after):
            if s and s.get("soc") is not None and s.get("mode") is not None:
                out.append(
                    Sample(t, s["soc"], s["mode"], s["grid_w"], s["load_w"])
                )
    return out


def kind(a, b, max_gap_s):
    if (b.t - a.t).total_seconds() > max_gap_s:
        return None
    if (
        a.mode == b.mode == 0
        and a.charge_w > 0
        and b.charge_w > 0
        and b.soc >= a.soc
    ):
        return "charge"
    if a.mode == b.mode == 2 and a.grid_w == b.grid_w == 0 and b.soc <= a.soc:
        return "discharge"
    return None


def find_runs(seq, max_gap_s):
    """Lists of consecutive samples, no more than ``max_gap_s`` apart, that are all charging or all discharging."""
    out = []
    current, current_kind = [], None
    for a, b in itertools.pairwise(seq):
        k = kind(a, b, max_gap_s)
        if k and k == current_kind and current[-1] is a:
            current.append(b)
            continue
        if len(current) > 1:
            out.append((current_kind, current))
        current, current_kind = ([a, b], k) if k else ([], None)
    if len(current) > 1:
        out.append((current_kind, current))
    return out


def widths(run_kind, run, run_id):
    """Energy per whole point crossed within the run."""
    energy = [0.0]
    for a, b in itertools.pairwise(run):
        pa = a.charge_w if run_kind == "charge" else a.load_w
        pb = b.charge_w if run_kind == "charge" else b.load_w
        energy.append(
            energy[-1] + (pa + pb) / 2 * (b.t - a.t).total_seconds() / 3600
        )
    crossed = {}
    for (a, ea), (b, eb) in itertools.pairwise(zip(run, energy)):
        k = abs(b.soc - a.soc)
        for j in range(1, k + 1):
            boundary = a.soc + j if run_kind == "charge" else a.soc - j + 1
            crossed[boundary] = ea + (j - 0.5) / k * (eb - ea)
    obs = []
    for boundary, e in crossed.items():
        if boundary + 1 in crossed:
            obs.append(
                Obs(boundary, abs(crossed[boundary + 1] - e), run_id, run[0].t)
            )
    return obs


def accepted(run, run_id):
    return [
        Obs(s.soc, s.charge_w, run_id, run[0].t)
        for s in run[1:-1]
        if s.soc < POINTS
    ]


class Runs:
    """Per run and point: count, sum and sum of squares of the observations."""

    def __init__(self, obs):
        self.ids = sorted({o.run for o in obs})
        self.t = {o.run: o.t for o in obs}
        self.c = {r: [0] * POINTS for r in self.ids}
        self.s = {r: [0.0] * POINTS for r in self.ids}
        self.q = {r: [0.0] * POINTS for r in self.ids}
        for o in obs:
            self.c[o.run][o.point] += 1
            self.s[o.run][o.point] += o.value
            self.q[o.run][o.point] += o.value**2
        self._spread = {}

    def spread(self, r, neighbour):
        """Run ``r``'s counts and sums shared out to neighbouring points."""
        key = (r, neighbour)
        if key not in self._spread:
            c, s = [0.0] * POINTS, [0.0] * POINTS
            for j in range(POINTS):
                if not self.c[r][j]:
                    continue
                for k in range(POINTS) if neighbour else (j,):
                    w = 0.5 ** (abs(k - j) / neighbour) if neighbour else 1.0
                    c[k] += w * self.c[r][j]
                    s[k] += w * self.s[r][j]
            self._spread[key] = (c, s)
        return self._spread[key]

    def age(self, r, now, half_life):
        return (
            1.0
            if half_life is None
            else 0.5 ** ((now - self.t[r]).total_seconds() / 86400 / half_life)
        )


def estimate(runs, prior, now, neighbour, half_life, weight, leave_out=None):
    num = [weight * p for p in prior]
    den = [weight] * POINTS
    for r in runs.ids:
        if r == leave_out:
            continue
        a = runs.age(r, now, half_life)
        c, s = runs.spread(r, neighbour)
        for k in range(POINTS):
            num[k] += a * s[k]
            den[k] += a * c[k]
    return [n / d for n, d in zip(num, den)]


def _error(runs, r, fit):
    c, s, q = runs.c[r], runs.s[r], runs.q[r]
    return sum(
        c[k] * fit[k] ** 2 - 2 * fit[k] * s[k] + q[k] for k in range(POINTS)
    )


def choose(runs, prior, now):
    """The settings that best predict each run from the others, their score, and the prior's."""
    n = sum(sum(runs.c[r]) for r in runs.ids)
    scores = {}
    for setting in itertools.product(
        NEIGHBOUR_HALF_POINTS, AGE_HALF_LIFE_DAYS, PRIOR_WEIGHT
    ):
        err = sum(
            _error(runs, r, estimate(runs, prior, now, *setting, leave_out=r))
            for r in runs.ids
        )
        scores[setting] = err / n
    best = min(scores, key=scores.get)
    return (
        best,
        scores[best],
        sum(_error(runs, r, prior) for r in runs.ids) / n,
    )


def fit(log, prior, now, max_gap_s):
    seq = samples(log)
    found = find_runs(seq, max_gap_s)
    obs = {"charge_wh": [], "yield_wh": [], "charge_w": []}
    for i, (k, run) in enumerate(found):
        if k == "charge":
            obs["charge_wh"] += widths(k, run, i)
            obs["charge_w"] += accepted(run, i)
        else:
            obs["yield_wh"] += widths(k, run, i)
    fitted, report = {}, {}
    for name, o in obs.items():
        p = getattr(prior, name)
        grouped = Runs(o)
        setting, score, prior_score = (
            choose(grouped, p, now) if o else ((0, None, 1), None, None)
        )
        fitted[name] = tuple(estimate(grouped, p, now, *setting))
        report[name] = {
            "observations": len(o),
            "runs": len(grouped.ids),
            "per_point": [
                sum(grouped.c[r][k] for r in grouped.ids)
                for k in range(POINTS)
            ],
            "neighbour_half_points": setting[0],
            "age_half_life_days": setting[1],
            "prior_weight": setting[2],
            "score": score,
            "prior_score": prior_score,
        }
    return Curve(**fitted), report


class Learner:
    """The battery with a curve fitted from the log, refitted once it is a day old."""

    def __init__(self, out, battery, max_gap_s):
        out = Path(out)
        self.log = out / "log.jsonl"
        self.path = out / "battery.json"
        self.fits_path = out / "battery_fits.jsonl"
        self.prior = battery
        self.max_gap_s = max_gap_s

    def battery(self, now):
        try:
            saved = json.loads(self.path.read_text())
        except FileNotFoundError:
            saved = None
        if (
            not saved
            or now - datetime.fromisoformat(saved["fitted_at"]) >= REFIT_EVERY
        ):
            started = datetime.now(timezone.utc)
            curve, report = fit(
                self.log, self.prior.curve, now, self.max_gap_s
            )
            saved = {
                **curve.to_json(),
                "report": report,
                "fitted_at": now.isoformat(),
                "seconds": round(
                    (datetime.now(timezone.utc) - started).total_seconds(), 1
                ),
            }
            self.path.write_text(json.dumps(saved))
            with open(self.fits_path, "a") as f:
                f.write(json.dumps(saved) + "\n")
        return (
            dataclasses.replace(self.prior, curve=Curve.load(self.path)),
            saved["fitted_at"],
        )


def main():
    import arbitrage

    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument("--out")
    args = p.parse_args()
    cfg, battery = arbitrage.load_config(args.config)
    log = f"{cfg['output']['dir']}/log.jsonl"
    curve, report = fit(
        log, battery.curve, datetime.now(timezone.utc), arbitrage.MAX_GAP_S
    )
    if args.out:
        with open(args.out, "w") as f:
            json.dump({**curve.to_json(), "report": report}, f)
    for name, r in report.items():
        print(name, {k: v for k, v in r.items() if k != "per_point"})
    print()
    print(
        " band     charge Wh/pt  yield Wh/pt  round trip  charger W  observations (charge/yield)"
    )
    for lo in range(0, POINTS, 10):
        band = range(lo, lo + 10)
        c = sum(curve.charge_wh[k] for k in band)
        y = sum(curve.yield_wh[k] for k in band)
        w = min(curve.charge_w[k] for k in band)
        n = (
            sum(report["charge_wh"]["per_point"][k] for k in band),
            sum(report["yield_wh"]["per_point"][k] for k in band),
        )
        print(
            f"{lo:3d}-{lo + 10:<3d}  {c / 10:12.1f}  {y / 10:11.1f}  {y / c:10.2f}  {w:9.0f}  {n[0]}/{n[1]}"
        )
    lo, hi = battery.floor_soc, battery.max_soc
    print(
        f"\nfloor to max: {curve.charge_cost(lo, hi):.0f} Wh in, {curve.yield_between(lo, hi):.0f} Wh out"
    )


if __name__ == "__main__":
    main()
