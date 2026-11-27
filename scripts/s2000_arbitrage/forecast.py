"""Probabilistic forecast of the rack's load, learnt from its own history.

    load = baseline + sum of switch contributions + residual

- Baseline: a low quantile of the trailing load less known switch contributions,
  so builds and other bursts don't move it but a hardware change does within hours.
- Switch contribution: the recency-weighted median step in load when the switch changes.
- Switch behaviour: per switch and direction, the chance of changing in the next
  fifteen minutes, from a logistic regression on time since the last change, time of
  day, weekend, the time of day the current state began, and price. An hour-of-week
  rate is used instead when it predicts the held-out days better.
- Residual: past residual paths, copied an hour at a time from moments at the same
  time of day with a similar residual, so bursts keep their length and calendar pattern.

The baseline window and the recency half-lives are chosen by ``fit`` from candidates,
by backtesting on the most recent days; ``fit`` returns its scores for the log.
"""

import bisect
import math
import random
from collections import deque
from datetime import timedelta, timezone

from history import STEP

PER_DAY = 288
PER_HOUR = 12

BASELINE_QUANTILE = 0.2
BASELINE_WINDOWS = (72, 288, 864)
HALF_LIVES_DAYS = (3, 10, 30)
DAY_TYPE_WEIGHTS = (1.0, 0.3)
DEFAULTS = {"window": 288, "half_life_days": 10, "day_type_weight": 1.0}

BLOCK = PER_HOUR
TOD_TOLERANCE = 3

HAZARD_STEP = 3
SWITCH_HALF_LIVES_DAYS = (7, 28, 112)
RIDGE = 1.0

BACKTEST_DAYS = 3
BACKTEST_EVERY = 36
BACKTEST_HORIZON = 144
BACKTEST_SCENARIOS = 32


def _utc(t):
    return t.astimezone(timezone.utc)


def _tod(t):
    u = _utc(t)
    return (u.hour * 60 + u.minute) // 5


def _weekend(t):
    return _utc(t).weekday() >= 5


def baselines(values, window):
    """Causal trailing ``BASELINE_QUANTILE`` of ``values`` over ``window`` buckets; ``None`` before any reading."""
    out, ordered, live = [], [], deque()
    for i, v in enumerate(values):
        if v is not None:
            bisect.insort(ordered, v)
            live.append((i, v))
        while live and live[0][0] <= i - window:
            del ordered[bisect.bisect_left(ordered, live.popleft()[1])]
        out.append(
            ordered[int(BASELINE_QUANTILE * (len(ordered) - 1))]
            if ordered
            else None
        )
    return out


def _weighted_median(pairs):
    pairs = sorted(pairs)
    total = sum(w for _, w in pairs)
    acc = 0.0
    for v, w in pairs:
        acc += w
        if acc >= total / 2:
            return v
    return 0.0


def switch_watts(series, half_life_days):
    """Each switch's contribution: the recency-weighted median load step when only it changed."""
    n = len(series)
    changes = {name: [] for name in series.switches}
    for name, states in series.switches.items():
        for j in range(1, n):
            if (
                states[j - 1] is not None
                and states[j] is not None
                and states[j - 1] != states[j]
            ):
                changes[name].append(j)
    out = {}
    for name, js in changes.items():
        others = [
            j for other, oj in changes.items() if other != name for j in oj
        ]
        steps = []
        for j in js:
            if any(abs(j - k) <= 3 for k in others):
                continue
            before = [
                v for v in series.load[max(0, j - 3) : j] if v is not None
            ]
            after = [v for v in series.load[j + 1 : j + 4] if v is not None]
            if not before or not after:
                continue
            d = sum(after) / len(after) - sum(before) / len(before)
            if not series.switches[name][j]:
                d = -d
            steps.append((d, 0.5 ** ((n - j) / PER_DAY / half_life_days)))
        out[name] = {
            "watts": _weighted_median(steps) if steps else 0.0,
            "steps_seen": len(steps),
        }
    return out


def residuals(series, base, watts):
    out = []
    for i, v in enumerate(series.load):
        if v is None or base[i] is None:
            out.append(None)
            continue
        on = sum(
            watts[name]["watts"]
            for name, states in series.switches.items()
            if states[i]
        )
        out.append(v - base[i] - on)
    return out


class ResidualPaths:
    """Samples future residual paths by copying history from similar moments."""

    def __init__(
        self, series, resid, half_life_days, day_type_weight, upto=None
    ):
        self.resid = resid
        self.upto = len(resid) if upto is None else upto
        self.half_life = half_life_days
        self.day_weight = day_type_weight
        self.weekend = [_weekend(series.time(i)) for i in range(self.upto)]
        self.by_tod = {}
        for i in range(self.upto - 1):
            if resid[i] is not None and resid[i + 1] is not None:
                self.by_tod.setdefault(_tod(series.time(i)), []).append(i)
        known = sorted(abs(r) for r in resid[: self.upto] if r is not None)
        mad = known[len(known) // 2] if known else 0.0
        self.bandwidth = max(1.4826 * mad, 5.0)

    def _pick(self, t, current, rng):
        tod = _tod(t)
        weekend = _weekend(t)
        cands, weights = [], []
        for k in range(-TOD_TOLERANCE, TOD_TOLERANCE + 1):
            for i in self.by_tod.get((tod + k) % PER_DAY, ()):
                w = 0.5 ** ((self.upto - i) / PER_DAY / self.half_life)
                if self.weekend[i] != weekend:
                    w *= self.day_weight
                z = (self.resid[i] - current) / self.bandwidth
                w *= math.exp(-0.5 * z * z)
                if w > 0:
                    cands.append(i)
                    weights.append(w)
        if not cands:
            return None
        return rng.choices(cands, weights)[0]

    def path(self, t0, current, n, rng):
        """Residuals for the ``n`` buckets after the one at ``t0``, whose residual is ``current``."""
        out = []
        while len(out) < n:
            i = self._pick(t0 + len(out) * STEP, current, rng)
            if i is None:
                out.extend([0.0] * (n - len(out)))
                break
            for k in range(1, BLOCK + 1):
                j = i + k
                if len(out) == n or j >= self.upto or self.resid[j] is None:
                    break
                current = self.resid[j]
                out.append(current)
        return out


def _features(t, since_steps, began, price):
    d = since_steps / PER_HOUR
    tod = _tod(t) / PER_DAY
    b = _tod(began) / PER_DAY
    return [
        1.0,
        math.log1p(d),
        math.exp(-d / 0.5),
        math.exp(-d / 2),
        math.exp(-d / 8),
        math.sin(2 * math.pi * tod),
        math.cos(2 * math.pi * tod),
        math.sin(4 * math.pi * tod),
        math.cos(4 * math.pi * tod),
        1.0 if _weekend(t) else 0.0,
        math.sin(2 * math.pi * b),
        math.cos(2 * math.pi * b),
        (price if price is not None else 0.0) / 100,
    ]


def _sigmoid(z):
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z))))


def _solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        if abs(m[c][c]) < 1e-12:
            continue
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                for k in range(c, n + 1):
                    m[r][k] -= f * m[c][k]
    return [
        m[i][n] / m[i][i] if abs(m[i][i]) > 1e-12 else 0.0 for i in range(n)
    ]


def fit_logistic(rows, iterations=8):
    """Ridge logistic regression by Newton's method; ``rows`` are (features, outcome, weight)."""
    k = len(rows[0][0])
    beta = [0.0] * k
    for _ in range(iterations):
        grad = [0.0] * k
        hess = [[0.0] * k for _ in range(k)]
        for x, y, w in rows:
            p = _sigmoid(sum(b * v for b, v in zip(beta, x)))
            r, s = w * (y - p), w * p * (1 - p)
            for a in range(k):
                grad[a] += r * x[a]
                sa = s * x[a]
                row = hess[a]
                for c in range(a, k):
                    row[c] += sa * x[c]
        for a in range(k):
            for c in range(a):
                hess[a][c] = hess[c][a]
            if a:
                grad[a] -= RIDGE * beta[a]
                hess[a][a] += RIDGE
        step = _solve(hess, grad)
        beta = [b + d for b, d in zip(beta, step)]
        if max(abs(d) for d in step) < 1e-6:
            break
    return beta


def _how(t):
    u = _utc(t)
    return u.weekday() * 24 + u.hour


class Hazard:
    """Chance a switch changes state in the next ``HAZARD_STEP`` buckets."""

    def __init__(self, spec):
        self.spec = spec

    def p(self, t, since_steps, began, price):
        if self.spec["kind"] == "logistic":
            x = _features(t, since_steps, began, price)
            return _sigmoid(sum(b * v for b, v in zip(self.spec["beta"], x)))
        if self.spec["kind"] == "hour_of_week":
            return self.spec["rates"][_how(t)]
        return 0.0


def _hazard_rows(series, name, price_at):
    """(time, state, since, began, price, changed) every ``HAZARD_STEP`` buckets where the switch is known."""
    states = series.switches[name]
    rows, since, began, prev = [], 0, None, None
    for i in range(0, len(states) - HAZARD_STEP, HAZARD_STEP):
        s, nxt = states[i], states[i + HAZARD_STEP]
        t = series.time(i)
        if s is None or nxt is None:
            prev, since, began = None, 0, None
            continue
        if s != prev:
            since, began = 0, t
        rows.append((i, t, s, since, began, price_at(t), nxt != s))
        since += HAZARD_STEP
        prev = s
    return rows


def _log_loss(model, rows):
    total = 0.0
    for _, t, _, since, began, price, changed in rows:
        p = min(max(model.p(t, since, began, price), 1e-6), 1 - 1e-6)
        total -= math.log(p if changed else 1 - p)
    return total / max(len(rows), 1)


def _fit_hazard(rows, n, half_life_days):
    weighted = [
        (r, 0.5 ** ((n - r[0]) / PER_DAY / half_life_days)) for r in rows
    ]
    yield (
        "logistic",
        half_life_days,
        Hazard(
            {
                "kind": "logistic",
                "beta": fit_logistic(
                    [
                        (
                            _features(t, since, began, price),
                            1.0 if changed else 0.0,
                            w,
                        )
                        for (
                            _,
                            t,
                            _,
                            since,
                            began,
                            price,
                            changed,
                        ), w in weighted
                    ]
                ),
            }
        ),
    )
    total = sum(w for _, w in weighted)
    mean = sum(w for r, w in weighted if r[6]) / total if total else 0.0
    sums = {}
    for r, w in weighted:
        s = sums.setdefault(_how(r[1]), [0.0, 0.0])
        s[0] += w * r[6]
        s[1] += w
    rates = [
        (sums.get(h, [0, 0])[0] + 2 * mean) / (sums.get(h, [0, 0])[1] + 2)
        for h in range(168)
    ]
    yield "hour_of_week", half_life_days, Hazard(
        {"kind": "hour_of_week", "rates": rates}
    )


def fit_switch(series, name, price_at):
    """Choose and fit both hazards for one switch; returns specs and held-out scores."""
    rows = _hazard_rows(series, name, price_at)
    n = len(series)
    out = {}
    for state, label in ((True, "off"), (False, "on")):
        mine = [r for r in rows if r[2] == state]
        changes = sum(1 for r in mine if r[6])
        if changes < 2:
            out[label] = {
                "spec": {"kind": "none"},
                "changes_seen": changes,
                "scores": {},
            }
            continue
        held_from = n - 7 * PER_DAY
        train = [r for r in mine if r[0] < held_from]
        test = [r for r in mine if r[0] >= held_from]
        scores = {}
        if train and test and sum(1 for r in train if r[6]) >= 2:
            for half_life in SWITCH_HALF_LIVES_DAYS:
                for kind, hl, model in _fit_hazard(
                    train, held_from, half_life
                ):
                    scores[f"{kind}/{hl}"] = round(_log_loss(model, test), 5)
            kind, hl = min(scores, key=scores.get).split("/")
        else:
            kind, hl = "hour_of_week", str(SWITCH_HALF_LIVES_DAYS[1])
        model = next(
            m for k, _, m in _fit_hazard(mine, n, int(hl)) if k == kind
        )
        out[label] = {
            "spec": model.spec,
            "chosen": f"{kind}/{hl}",
            "changes_seen": changes,
            "scores": scores,
        }
    return out


def _crps(samples, actual):
    n = len(samples)
    s = sorted(samples)
    spread = sum((2 * (i + 1) - n - 1) * v for i, v in enumerate(s)) / (n * n)
    return sum(abs(v - actual) for v in s) / n - spread


def _backtest(series, base, watts, half_life, day_weight, rng):
    resid = residuals(series, base, watts)
    n = len(series)
    origins = range(
        max(n - BACKTEST_DAYS * PER_DAY, 2 * PER_DAY),
        n - BACKTEST_HORIZON,
        BACKTEST_EVERY,
    )
    total, count = 0.0, 0
    for o in origins:
        if resid[o] is None:
            continue
        paths = ResidualPaths(series, resid, half_life, day_weight, upto=o + 1)
        actual = series.load[o + 1 : o + 1 + BACKTEST_HORIZON]
        on = [
            sum(
                watts[name]["watts"]
                for name, states in series.switches.items()
                if states[o + 1 + k]
            )
            for k in range(BACKTEST_HORIZON)
        ]
        sims = [
            [
                base[o] + on[k] + r
                for k, r in enumerate(
                    paths.path(series.time(o), resid[o], BACKTEST_HORIZON, rng)
                )
            ]
            for _ in range(BACKTEST_SCENARIOS)
        ]
        for h in (24, 72, 144):
            known = [k for k in range(h) if actual[k] is not None]
            if len(known) < h / 2:
                continue
            truth = (
                sum(actual[k] for k in known)
                / len(known)
                * h
                / PER_HOUR
                / 1000
            )
            preds = [sum(s[:h]) / PER_HOUR / 1000 for s in sims]
            total += _crps(preds, truth) / (h / PER_HOUR)
            count += 1
    return total / count if count else None


def fit(series, price_at, seed=0):
    """Choose the baseline window and residual weighting by backtest, and fit each switch."""
    rng = random.Random(seed)
    chosen = dict(DEFAULTS)
    scores = {}
    enough = len(series) >= (BACKTEST_DAYS + 2) * PER_DAY
    if enough:
        watts = switch_watts(series, chosen["half_life_days"])
        for key, candidates in (
            ("window", BASELINE_WINDOWS),
            ("half_life_days", HALF_LIVES_DAYS),
            ("day_type_weight", DAY_TYPE_WEIGHTS),
        ):
            results = {}
            for c in candidates:
                trial = dict(chosen, **{key: c})
                base = baselines(
                    _less_switches(series, watts), trial["window"]
                )
                results[c] = _backtest(
                    series,
                    base,
                    watts,
                    trial["half_life_days"],
                    trial["day_type_weight"],
                    rng,
                )
            scores[key] = {
                str(c): (round(s, 5) if s is not None else None)
                for c, s in results.items()
            }
            valid = {c: s for c, s in results.items() if s is not None}
            if valid:
                chosen[key] = min(valid, key=valid.get)
    switches = {
        name: fit_switch(series, name, price_at) for name in series.switches
    }
    return {
        **chosen,
        "backtested": enough,
        "scores": scores,
        "switches": switches,
    }


def _less_switches(series, watts):
    return [
        (
            None
            if v is None
            else v
            - sum(
                watts[name]["watts"]
                for name, states in series.switches.items()
                if states[i]
            )
        )
        for i, v in enumerate(series.load)
    ]


class Forecaster:
    """Scenarios of the load in each future five-minute bucket, from the latest reading."""

    def __init__(self, series, model):
        self.series = series
        self.model = model
        self.watts = switch_watts(series, model["half_life_days"])
        self.base = baselines(
            _less_switches(series, self.watts), model["window"]
        )
        self.resid = residuals(series, self.base, self.watts)
        self.paths = ResidualPaths(
            series,
            self.resid,
            model["half_life_days"],
            model["day_type_weight"],
        )
        self.last = max(
            (
                i
                for i, v in enumerate(series.load)
                if v is not None and self.base[i] is not None
            ),
            default=None,
        )
        self.hazards = {
            name: {
                d: Hazard(spec["spec"])
                for d, spec in self.model["switches"].get(name, {}).items()
            }
            for name in series.switches
        }

    def now(self):
        return {
            "baseline_w": self.base[self.last],
            "residual_w": self.resid[self.last],
            "switch_w": self.watts,
        }

    def _switch_path(self, name, n, rng, price_at):
        states = self.series.switches[name]
        state = states[self.last]
        if state is None:
            return [False] * n
        i, since = self.last, 0
        while i > 0 and states[i - 1] == state:
            i -= 1
            since += 1
        began = self.series.time(i)
        out = []
        for k in range(n):
            t = self.series.time(self.last + 1 + k)
            if k % HAZARD_STEP == 0:
                hz = self.hazards[name].get("off" if state else "on")
                if hz and rng.random() < hz.p(t, since, began, price_at(t)):
                    state, since, began = not state, 0, t
            out.append(state)
            since += 1
        return out

    def scenarios(self, n_steps, count, price_at, seed=0):
        """``count`` lists of watts for the ``n_steps`` buckets after the latest reading."""
        rng = random.Random(seed)
        t0 = self.series.time(self.last)
        out = []
        for _ in range(count):
            resid = self.paths.path(t0, self.resid[self.last], n_steps, rng)
            on = [0.0] * n_steps
            for name in self.series.switches:
                w = self.watts[name]["watts"]
                for k, s in enumerate(
                    self._switch_path(name, n_steps, rng, price_at)
                ):
                    if s:
                        on[k] += w
            out.append(
                [
                    max(0.0, self.base[self.last] + on[k] + resid[k])
                    for k in range(n_steps)
                ]
            )
        return out

    def first_time(self):
        return self.series.time(self.last + 1)


def slot_means(scenario, first, slots):
    """Mean watts of a bucket ``scenario`` starting at ``first`` over each slot."""
    out = []
    for slot in slots:
        a = slot.start
        b = slot.start + timedelta(hours=slot.hours)
        total = secs = 0.0
        k = max(0, int((a - first) // STEP))
        while k < len(scenario):
            lo = first + k * STEP
            hi = lo + STEP
            if lo >= b:
                break
            overlap = (min(hi, b) - max(lo, a)).total_seconds()
            if overlap > 0:
                total += scenario[k] * overlap
                secs += overlap
            k += 1
        out.append(
            total / secs if secs else (scenario[-1] if scenario else 0.0)
        )
    return out
