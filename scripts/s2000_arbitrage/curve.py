"""A battery described per SoC point instead of by capacity and efficiencies.

For each point ``k`` (SoC ``k`` to ``k + 1``):

- ``charge_wh[k]``: grid energy, above the load, that raises SoC by the point.
- ``yield_wh[k]``: load energy the battery delivers while SoC falls by the point.
- ``charge_w[k]``: the most the charger accepts at that point.

SoC between whole points is filled linearly, so every quantity is a
piecewise-linear function of SoC.
"""

import bisect
import json
from dataclasses import dataclass

POINTS = 100


@dataclass(frozen=True)
class Curve:
    charge_wh: tuple[float, ...]
    yield_wh: tuple[float, ...]
    charge_w: tuple[float, ...]

    @classmethod
    def flat(
        cls, capacity_wh, charge_efficiency, discharge_efficiency, charge_w
    ):
        point = capacity_wh / POINTS
        return cls(
            charge_wh=(point / charge_efficiency,) * POINTS,
            yield_wh=(point * discharge_efficiency,) * POINTS,
            charge_w=(float(charge_w),) * POINTS,
        )

    @classmethod
    def load(cls, path):
        with open(path) as f:
            d = json.load(f)
        return cls(
            tuple(d["charge_wh"]), tuple(d["yield_wh"]), tuple(d["charge_w"])
        )

    def to_json(self):
        return {
            "charge_wh": list(self.charge_wh),
            "yield_wh": list(self.yield_wh),
            "charge_w": list(self.charge_w),
        }

    def charge_cost(self, a, b):
        """Grid Wh to charge from ``a`` to ``b`` percent."""
        return _integral(self._sums("charge_wh"), b) - _integral(
            self._sums("charge_wh"), a
        )

    def yield_between(self, a, b):
        """Load Wh delivered discharging from ``b`` down to ``a`` percent."""
        return _integral(self._sums("yield_wh"), b) - _integral(
            self._sums("yield_wh"), a
        )

    def charge_hours(self, a, b, limit_w):
        """Hours to charge from ``a`` to ``b`` percent with the charger limited to ``limit_w``."""
        return _integral(self._sums(limit_w), b) - _integral(
            self._sums(limit_w), a
        )

    def after_charge(self, a, hours, limit_w, hi):
        """SoC after charging from ``a`` for ``hours``, stopping at ``hi``."""
        sums = self._sums(limit_w)
        return min(hi, _inverse(sums, _integral(sums, a) + hours))

    def after_discharge(self, a, load_wh, lo):
        """SoC after delivering ``load_wh`` from ``a``, stopping at ``lo``."""
        if a <= lo:
            return a
        sums = self._sums("yield_wh")
        return max(lo, _inverse(sums, _integral(sums, a) - load_wh))

    def _sums(self, key):
        """Running totals from SoC 0 of a per-point quantity; a number means hours at that charger limit."""
        cache = self.__dict__.setdefault("_cache", {})
        if key not in cache:
            if isinstance(key, str):
                per_point = getattr(self, key)
            else:
                per_point = [
                    wh / min(key, w)
                    for wh, w in zip(self.charge_wh, self.charge_w)
                ]
            sums = [0.0]
            for v in per_point:
                sums.append(sums[-1] + v)
            cache[key] = sums
        return cache[key]


def _integral(sums, soc):
    soc = min(max(soc, 0.0), POINTS)
    k = min(int(soc), POINTS - 1)
    return sums[k] + (soc - k) * (sums[k + 1] - sums[k])


def _inverse(sums, total):
    """The SoC at which ``_integral(sums, soc)`` reaches ``total``."""
    if total <= 0:
        return 0.0
    if total >= sums[-1]:
        return float(POINTS)
    k = bisect.bisect_right(sums, total) - 1
    return k + (total - sums[k]) / (sums[k + 1] - sums[k])
