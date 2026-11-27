"""Schedules that minimise expected cost over load scenarios.

Starts from the dynamic-programming schedule for the mean load, then improves it
by local search, scoring each candidate by simulating every scenario exactly
(no energy steps): selling carries the load until the floor and the grid
covers the rest, so running short costs the price of the slot it happens in.
Moves are single-slot changes and moving a sell to a later, pricier hold
slot. A change is kept only if it lowers the expected cost by ``MARGIN_P``.
"""

import time

import optimise

MARGIN_P = 0.05
PASSES = 4


class Evaluator:
    def __init__(self, slots, soc, scenarios, battery, terminal):
        self.slots = slots
        self.scenarios = scenarios
        self.battery = battery
        self.terminal = terminal
        self.curve = battery.curve
        self.lo = battery.floor_soc
        self.hi = battery.max_soc
        self.e0 = soc

    def step(self, e, action, buy_w, watts, slot):
        """SoC after the slot and grid Wh bought in it."""
        load_wh = watts * slot.hours
        if action == "sell":
            after = self.curve.after_discharge(e, load_wh, self.lo)
            return after, load_wh - self.curve.yield_between(after, e)
        if action == "buy":
            after = max(
                e, self.curve.after_charge(e, slot.hours, buy_w, self.hi)
            )
            return after, load_wh + self.curve.charge_cost(e, after)
        return e, load_wh

    def prefix(self, actions):
        """Per slot, each scenario's energy and cost so far at its start."""
        energy = [[self.e0] * len(self.scenarios)]
        cost = [[0.0] * len(self.scenarios)]
        for k, slot in enumerate(self.slots):
            action, buy_w = actions[k]
            es, cs = [], []
            for s, loads in enumerate(self.scenarios):
                e, grid = self.step(
                    energy[k][s], action, buy_w, loads[k], slot
                )
                es.append(e)
                cs.append(cost[k][s] + grid / 1000 * slot.price)
            energy.append(es)
            cost.append(cs)
        return energy, cost

    def score_from(self, actions, i, energy, cost):
        total = 0.0
        for s, loads in enumerate(self.scenarios):
            e, c = energy[s], cost[s]
            for k in range(i, len(self.slots)):
                action, buy_w = actions[k]
                e, grid = self.step(e, action, buy_w, loads[k], self.slots[k])
                c += grid / 1000 * self.slots[k].price
            total += c - optimise.stored_value_p(
                self.battery, e, self.terminal
            )
        return total / len(self.scenarios)


def plan(slots, soc, scenarios, battery, terminal, first=None):
    """Return (steps for the mean load, details for the log)."""
    started = time.monotonic()
    mean = [sum(col) / len(col) for col in zip(*scenarios)]
    deterministic = optimise.plan(
        slots, soc, mean, battery, terminal, first=first
    )
    actions = [(s.action, s.buy_w) for s in deterministic]
    ev = Evaluator(slots, soc, scenarios, battery, terminal)
    energy, cost = ev.prefix(actions)
    best = start = ev.score_from(actions, 0, energy[0], cost[0])
    options = [("hold", 0), ("sell", 0)] + [
        ("buy", c) for c in sorted(battery.charge_limits_w)
    ]
    evaluations = 1
    fixed = 1 if first else 0

    def consider(trial, i):
        nonlocal best, actions, energy, cost, evaluations
        evaluations += 1
        v = ev.score_from(trial, i, energy[i], cost[i])
        if v < best - MARGIN_P:
            best, actions = v, trial
            energy, cost = ev.prefix(actions)
            return True
        return False

    for _ in range(PASSES):
        improved = False
        for i in range(fixed, len(slots)):
            for option in options:
                if option != actions[i] and consider(
                    actions[:i] + [option] + actions[i + 1 :], i
                ):
                    improved = True
        for i in range(fixed, len(slots)):
            if actions[i][0] != "sell":
                continue
            for j in range(i + 1, len(slots)):
                if actions[j][0] == "hold" and slots[j].price > slots[i].price:
                    trial = list(actions)
                    trial[i], trial[j] = ("hold", 0), ("sell", 0)
                    if consider(trial, i):
                        improved = True
                        break
        if not improved:
            break
    steps = steps_for(slots, actions, soc, mean, battery)
    changed = [
        (s.slot.start.isoformat(), d.action, s.action)
        for s, d in zip(steps, deterministic)
        if (s.action, s.buy_w) != (d.action, d.buy_w)
    ]
    return steps, {
        "expected_p": round(best, 3),
        "mean_load_plan_expected_p": round(start, 3),
        "changed_from_mean_load_plan": changed,
        "evaluations": evaluations,
        "seconds": round(time.monotonic() - started, 2),
    }


def steps_for(slots, actions, soc, loads, battery):
    ev = Evaluator(slots, soc, [loads], battery, 0)
    e = ev.e0
    steps = []
    for slot, (action, buy_w), watts in zip(slots, actions, loads):
        after, grid = ev.step(e, action, buy_w, watts, slot)
        steps.append(
            optimise.Step(
                slot=slot,
                action=action,
                buy_w=buy_w,
                soc_start=e,
                soc_end=after,
                grid_kwh=grid / 1000,
                cost_p=grid / 1000 * slot.price,
            )
        )
        e = after
    return steps
