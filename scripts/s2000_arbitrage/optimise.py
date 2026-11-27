"""Cost-minimising schedule for a UPS battery on a half-hourly tariff.

The battery sits between the grid and a load given per slot. Each slot it does one
of three things:

- ``buy``: the load runs on pass-through and the charger adds ``buy_w``.
- ``sell``: the battery carries the load until it reaches the floor, after
  which the grid takes over. Nothing is exported; the stored energy is sold
  to our own load instead of buying from the grid.
- ``hold``: the load runs on pass-through and the battery is left alone.

Nothing is ever exported. The schedule minimises what is paid for grid energy
over the known prices, with the charge left at the end valued at what it would
cost to buy, at ``terminal_p_per_kwh``. How much energy each SoC point takes
and gives back comes from the battery's ``curve.Curve``. Dynamic programming
over SoC in ``STEP_SOC`` increments keeps it exact for this model and
dependency-free.
"""

import math
from dataclasses import dataclass
from datetime import datetime

from curve import Curve

STEP_SOC = 0.5


@dataclass(frozen=True)
class Battery:
    curve: Curve
    floor_soc: float
    max_soc: float
    charge_limits_w: tuple[int, ...]


@dataclass(frozen=True)
class Slot:
    start: datetime
    hours: float
    price: float


@dataclass(frozen=True)
class Step:
    slot: Slot
    action: str
    buy_w: int
    soc_start: float
    soc_end: float
    grid_kwh: float
    cost_p: float


def _moves(i, slot, load_w, battery, lo, hi):
    load_wh = load_w * slot.hours
    curve = battery.curve
    soc = i * STEP_SOC
    yield "hold", 0, i, load_wh
    j = min(
        i,
        max(
            lo,
            round(
                curve.after_discharge(soc, load_wh, lo * STEP_SOC) / STEP_SOC
            ),
        ),
    )
    delivered = min(curve.yield_between(j * STEP_SOC, soc), load_wh)
    yield "sell", 0, j, load_wh - delivered
    seen = set()
    for c in sorted(battery.charge_limits_w):
        j = min(
            round(curve.after_charge(soc, slot.hours, c, 100) / STEP_SOC), hi
        )
        if j <= i or j in seen:
            continue
        seen.add(j)
        yield "buy", c, j, load_wh + curve.charge_cost(soc, j * STEP_SOC)


def plan(slots, soc, load_w, battery, terminal_p_per_kwh, first=None):
    """Return the cheapest ``Step`` per slot, starting from ``soc`` percent.

    ``load_w`` is watts for every slot, or one figure per slot. ``first`` forces the first slot's action.
    """
    loads = _per_slot(load_w, slots)
    levels = round(100 / STEP_SOC)
    lo = math.ceil(battery.floor_soc / STEP_SOC)
    hi = math.floor(battery.max_soc / STEP_SOC)
    start = min(max(round(soc / STEP_SOC), 0), levels)

    cost_to_go = [
        -stored_value_p(battery, i * STEP_SOC, terminal_p_per_kwh)
        for i in range(levels + 1)
    ]
    choices = []
    for slot, load in zip(reversed(slots), reversed(loads)):
        best_cost = [math.inf] * (levels + 1)
        best_move = [None] * (levels + 1)
        for i in range(levels + 1):
            for action, buy_w, j, grid_wh in _moves(
                i, slot, load, battery, lo, hi
            ):
                if first and slot is slots[0] and action != first:
                    continue
                cost = grid_wh / 1000 * slot.price + cost_to_go[j]
                if cost < best_cost[i] - 1e-9:
                    best_cost[i] = cost
                    best_move[i] = (action, buy_w, j, grid_wh)
        cost_to_go = best_cost
        choices.append(best_move)
    choices.reverse()

    steps = []
    i = start
    for slot, moves in zip(slots, choices):
        action, buy_w, j, grid_wh = moves[i]
        steps.append(
            Step(
                slot=slot,
                action=action,
                buy_w=buy_w,
                soc_start=i * STEP_SOC,
                soc_end=j * STEP_SOC,
                grid_kwh=grid_wh / 1000,
                cost_p=grid_wh / 1000 * slot.price,
            )
        )
        i = j
    return steps


def baseline_cost_p(slots, load_w):
    """What the load alone would cost with no battery."""
    return sum(
        w * s.hours / 1000 * s.price
        for s, w in zip(slots, _per_slot(load_w, slots))
    )


def _per_slot(load_w, slots):
    return (
        list(load_w)
        if isinstance(load_w, (list, tuple))
        else [load_w] * len(slots)
    )


def terminal_value(slots, cheapest=8):
    """The price of the cheapest known slots, at which charge left at the end is valued."""
    prices = sorted(s.price for s in slots)[:cheapest]
    if not prices:
        return 0.0
    return max(0.0, sum(prices) / len(prices))


def stored_value_p(battery, soc, terminal_p_per_kwh):
    """What charging from empty to ``soc`` would cost at ``terminal_p_per_kwh``."""
    return battery.curve.charge_cost(0, soc) / 1000 * terminal_p_per_kwh
