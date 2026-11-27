"""Load scenarios per slot for the planner: history, nightly refits, forecasts."""

import bisect
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import forecast
import history

SCENARIOS = 64
REFIT_EVERY = timedelta(hours=24)
HISTORY = timedelta(days=90)


def price_lookup(rates):
    """Price at a time from (start, end, price) rates; None outside them."""
    rates = sorted(rates)
    starts = [r[0] for r in rates]

    def price_at(t):
        i = bisect.bisect_right(starts, t) - 1
        return rates[i][2] if i >= 0 and t < rates[i][1] else None

    return price_at


class Loads:
    def __init__(self, out, switches):
        out = Path(out)
        self.history = history.History(out / "loads.jsonl")
        self.model_path = out / "model.json"
        self.fits_path = out / "fits.jsonl"
        self.switches = list(switches)

    def record(self, now, watts, switches):
        self.history.append(now, watts, switches)

    def _series(self, now):
        return self.history.bucketed(self.switches, since=now - HISTORY)

    def model(self, now, fetch_rates):
        """The fitted model, refitting first if it is a day old or the switches changed.

        ``fetch_rates(since)`` returns (start, end, price) rates from ``since``.
        """
        try:
            model = json.loads(self.model_path.read_text())
        except FileNotFoundError:
            model = None
        if model and model.get("switch_names") == self.switches:
            if now - datetime.fromisoformat(model["fitted_at"]) < REFIT_EVERY:
                return model
        series = self._series(now)
        rates = fetch_rates(series.start)
        started = datetime.now(timezone.utc)
        model = forecast.fit(series, price_lookup(rates))
        model.update(
            fitted_at=now.isoformat(),
            switch_names=self.switches,
            buckets=len(series),
            seconds=round(
                (datetime.now(timezone.utc) - started).total_seconds(), 1
            ),
        )
        self.model_path.write_text(json.dumps(model))
        with open(self.fits_path, "a") as f:
            f.write(json.dumps(model) + "\n")
        return model

    def scenarios(self, now, slots, rates, model):
        """Per scenario, the mean watts in each slot; plus a summary for the log."""
        series = self._series(now)
        f = forecast.Forecaster(series, model)
        first = f.first_time()
        end = slots[-1].start + timedelta(hours=slots[-1].hours)
        n = max(1, int((end - first) / history.STEP) + 1)
        raw = f.scenarios(
            n, SCENARIOS, price_lookup(rates), seed=int(now.timestamp()) // 300
        )
        per_slot = [forecast.slot_means(s, first, slots) for s in raw]
        info = {
            **f.now(),
            "model": {
                k: model[k]
                for k in (
                    "window",
                    "half_life_days",
                    "day_type_weight",
                    "fitted_at",
                )
            },
            "slots_w": [
                [
                    slots[k].start.isoformat(),
                    *_quantiles([s[k] for s in per_slot]),
                ]
                for k in range(min(12, len(slots)))
            ],
            "energy_kwh": {
                label: _quantiles(
                    [
                        sum(
                            s[k] * slots[k].hours
                            for k in range(len(slots))
                            if slots[k].start < now + span
                        )
                        / 1000
                        for s in per_slot
                    ]
                )
                for label, span in (
                    ("2h", timedelta(hours=2)),
                    ("6h", timedelta(hours=6)),
                    ("12h", timedelta(hours=12)),
                    ("all", end - now),
                )
            },
        }
        return per_slot, info


def _quantiles(values):
    v = sorted(values)
    return [round(v[int(q * (len(v) - 1))], 3) for q in (0.1, 0.5, 0.9)]
