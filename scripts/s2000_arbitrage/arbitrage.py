"""Trade a UPS battery against a half-hourly tariff: buy, sell or hold each cycle.

    arbitrage.py --config FILE run [--dry-run] [--once]
    arbitrage.py --config FILE plan [--soc PCT] [--load W] [--curve battery.json]

The strategy knows nothing about the battery or where its inputs come from. It
runs the commands in ``[commands]``, each of which prints JSON:

- ``battery``: at least ``soc`` and ``load_w``; ``grid_connected`` false raises an alarm.
- ``prices``, called with ``--from ISO``: ``[[start, end, p/kWh], ...]``.
- ``switches``, called with the entity names from ``[forecast] switches``:
  ``{name: true | false | null}``.
- ``meter`` (optional, for the log only): anything.
- ``free`` (optional): booked free-electricity windows ``[[start, end], ...]``,
  priced at 0 p/kWh.
- ``position``, called with ``buy``, ``sell`` or ``hold``: what it did.

Each cycle re-plans from the battery's state, the published prices and a
probabilistic forecast of the load (forecast.py, stochastic.py), asks for the
current slot's position, and logs everything to ``[output] dir``.
"""

import argparse
import asyncio
import dataclasses
import json
import random
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import config
import curve_fit
import loads
import optimise
import stochastic
from curve import Curve

CYCLE = timedelta(minutes=5)
BUYING_CYCLE = timedelta(minutes=1)
RETRIES = 3
RETRY_DELAY = 30
COMMAND_TIMEOUT = 360
SWITCH_MARGIN_P = 1.0
MAX_GAP_S = CYCLE.total_seconds() + RETRIES * RETRY_DELAY


def load_config(path):
    cfg = config.load(path)
    b = cfg["battery"]
    battery = optimise.Battery(
        curve=Curve.flat(
            b["capacity_wh"],
            b["charge_efficiency"],
            b["discharge_efficiency"],
            b["buy_w"],
        ),
        floor_soc=b["floor_soc"],
        max_soc=b["max_soc"],
        charge_limits_w=(b["buy_w"],),
    )
    return cfg, battery


def call(cfg, name, *args):
    """Run the ``[commands]`` entry ``name`` with ``args`` and parse its JSON output."""
    proc = subprocess.run(
        [*cfg["commands"][name], *args],
        capture_output=True,
        text=True,
        timeout=COMMAND_TIMEOUT,
    )
    if proc.returncode:
        raise RuntimeError(
            f"{name} exited {proc.returncode}: {proc.stderr.strip()[-300:]}"
        )
    return json.loads(proc.stdout)


def fetch_rates(cfg, since):
    return [
        (datetime.fromisoformat(s), datetime.fromisoformat(e), price)
        for s, e, price in call(cfg, "prices", "--from", since.isoformat())
    ]


def free_windows(cfg, seen, record):
    """Booked free windows; the last ones seen if the command fails, so an API outage doesn't drop them."""
    if "free" not in cfg["commands"]:
        return []
    try:
        seen["free"] = call(cfg, "free")
    except Exception as e:
        record["free_error"] = repr(e)
    record["free"] = seen.get("free", [])
    return [
        (datetime.fromisoformat(s), datetime.fromisoformat(e))
        for s, e in record["free"]
    ]


def make_free(rates, windows):
    """Split rates at the windows' edges and price the parts inside a window at 0."""
    out = []
    for start, end, price in rates:
        cuts = sorted(
            {start, end, *(t for w in windows for t in w if start < t < end)}
        )
        for a, b in zip(cuts, cuts[1:]):
            out.append(
                (
                    a,
                    b,
                    (
                        0.0
                        if any(s <= a and b <= e for s, e in windows)
                        else price
                    ),
                )
            )
    return out


def slots_from(rates, now):
    """Slots still to come; the current one starts now, so energy already used in it isn't counted again."""
    return [
        optimise.Slot(
            start=max(start, now),
            hours=(end - max(start, now)).total_seconds() / 3600,
            price=price,
        )
        for start, end, price in rates
        if end > now
    ]


def render(steps, slots, soc, mean_w, terminal, info):
    base = optimise.baseline_cost_p(slots, mean_w)
    cost = sum(s.cost_p for s in steps)
    last = (
        slots[-1].start + timedelta(hours=slots[-1].hours) if slots else None
    )
    lines = [
        (
            f"SoC {soc}%, prices known until {last.astimezone():%a %H:%M}"
            if last
            else "no prices"
        ),
        f"Charge left at the end valued at {terminal:.2f} p/kWh bought",
        f"Grid cost {cost / 100:.2f} GBP vs {base / 100:.2f} GBP with no battery (mean load)",
        f"Expected cost over load scenarios {info['expected_p'] / 100:.2f} GBP after the end value",
        "",
        f"{'slot':<11} {'p/kWh':>7}  {'load W':>6}  {'position':<14} {'SoC':>11}  {'grid kWh':>8}",
    ]
    for s, w in zip(steps, mean_w):
        what = f"buy {s.buy_w} W" if s.action == "buy" else s.action
        lines.append(
            f"{s.slot.start.astimezone():%a %H:%M}  {s.slot.price:7.2f}  {w:6.0f}  {what:<14} "
            f"{s.soc_start:4.0f} → {s.soc_end:3.0f}%  {s.grid_kwh:8.3f}"
        )
    return "\n".join(lines)


def buy_session(steps, soc, battery, cfg, state, now):
    """Turn the planned run of buy slots into buy or hold for right now.

    Buying is always at full rate. If the run has more than the buffer of spare
    time, the start is delayed by a random amount within the spare, unless that
    would move buying into a pricier slot.
    """
    block = []
    for s in steps:
        if s.action != "buy":
            break
        block.append(s)
    end = block[-1].slot.start + timedelta(hours=block[-1].slot.hours)
    target = round(block[-1].soc_end)
    session = state.data.get("session")
    if not session or session["end"] != end.isoformat():
        needed_s = (
            battery.curve.charge_hours(
                soc, max(soc, target), max(battery.charge_limits_w)
            )
            * 3600
        )
        slack_s = (end - now).total_seconds() - needed_s
        buffer_s = cfg["buying"]["buffer_minutes"] * 60
        free = block[-1].slot.price <= block[0].slot.price
        delay_s = (
            random.uniform(0, slack_s - buffer_s)
            if free and slack_s > buffer_s
            else 0
        )
        session = {
            "end": end.isoformat(),
            "target": target,
            "needed_s": round(needed_s),
            "slack_s": round(slack_s),
            "free": free,
            "delay_s": round(delay_s),
            "start_after": (now + timedelta(seconds=delay_s)).isoformat(),
        }
        state.data["session"] = session
        state.save()
    if now < datetime.fromisoformat(session["start_after"]):
        return "hold", "waiting", session
    if soc >= target:
        return "hold", "target reached", session
    return "buy", "buying", session


def slot_end(step):
    return (step.slot.start + timedelta(hours=step.slot.hours)).isoformat()


def stick(position, steps, info, replan, state, record):
    """Within a slot, keep the position already taken unless switching saves more than SWITCH_MARGIN_P.

    ``replan(first)`` plans with the first slot's position forced.
    """
    step = steps[0]
    current = state.data.get("current", {})
    kept = current.get("position")
    if (
        current.get("end") != slot_end(step)
        or kept == position
        or {kept, position} != {"hold", "sell"}
    ):
        return position
    if step.action != position:
        return position
    _, other = replan(kept)
    saving = other["expected_p"] - info["expected_p"]
    record["switch_saving_p"] = round(saving, 3)
    return position if saving > SWITCH_MARGIN_P else kept


def stay_stopped(position, step, state, record):
    """Once selling stops partway through a slot, don't start it again until the next slot."""
    end = slot_end(step)
    if position == "sell" and state.data.get("stopped") == end:
        record["stopped"] = "selling stopped earlier in this slot"
        return "hold"
    if position == "sell":
        state.data["selling"] = end
    elif position == "hold" and state.data.get("selling") == end:
        state.data["stopped"] = end
    state.save()
    return position


class State:
    def __init__(self, path):
        self.path = Path(path)
        try:
            self.data = json.loads(self.path.read_text())
        except FileNotFoundError:
            self.data = {}

    def save(self):
        self.path.write_text(json.dumps(self.data))


def switch_names(cfg):
    return list(cfg.get("forecast", {}).get("switches", []))


def learner(cfg, battery):
    """Fits the battery's curve from the log when ``[battery] learn`` is set."""
    if cfg["battery"].get("learn"):
        return curve_fit.Learner(cfg["output"]["dir"], battery, MAX_GAP_S)
    return None


def cycle(cfg, battery, state, lm, learned, dry_run):
    now = datetime.now(timezone.utc)
    out = Path(cfg["output"]["dir"])
    record = {"t": now.isoformat()}
    if learned:
        battery, record["curve_fitted_at"] = learned.battery(now)
    published = fetch_rates(cfg, now - timedelta(minutes=30))
    free = free_windows(cfg, state.data, record)
    rates = make_free(published, free)
    slots = slots_from(rates, now)
    terminal = optimise.terminal_value(slots_from(published, now))
    model = lm.model(
        now, lambda since: make_free(fetch_rates(cfg, since), free)
    )
    switches = call(cfg, "switches", *lm.switches) if lm.switches else {}
    bat = call(cfg, "battery")
    record["battery"] = bat
    record["switches"] = switches
    lm.record(now, bat["load_w"], switches)
    scenarios, record["forecast"] = lm.scenarios(now, slots, rates, model)
    mean_w = [sum(col) / len(col) for col in zip(*scenarios)]
    replan = lambda first=None: stochastic.plan(
        slots, bat["soc"], scenarios, battery, terminal, first=first
    )
    steps, record["planner"] = replan()
    step = steps[0]
    position = step.action
    if position == "buy":
        position, record["buying"], record["session"] = buy_session(
            steps, bat["soc"], battery, cfg, state, now
        )
    position = stick(position, steps, record["planner"], replan, state, record)
    position = stay_stopped(position, step, state, record)
    state.data["current"] = {"end": slot_end(step), "position": position}
    state.save()
    record.update(
        price=step.slot.price,
        planned=step.action,
        position=position,
        plan=[
            (
                s.slot.start.isoformat(),
                s.slot.price,
                s.action,
                s.buy_w,
                round(s.soc_end, 1),
            )
            for s in steps[:8]
        ],
        plan_cost_p=sum(s.cost_p for s in steps),
        baseline_cost_p=optimise.baseline_cost_p(slots, mean_w),
    )
    if bat.get("grid_connected") is False:
        record["alarm"] = (
            "AC input disconnected: power cut or the plug's relay is off"
        )
        print(f"ALARM {record['alarm']}", flush=True)
    if "meter" in cfg["commands"]:
        try:
            record["meter"] = call(cfg, "meter")
        except Exception as e:
            record["meter"] = repr(e)
    if not dry_run:
        record["applied"] = call(cfg, "position", position)
    (out / "plan.txt").write_text(
        render(steps, slots, bat["soc"], mean_w, terminal, record["planner"])
        + "\n"
    )
    with open(out / "log.jsonl", "a") as f:
        f.write(json.dumps(record) + "\n")
    print(
        f"{now.astimezone():%H:%M:%S} SoC {bat['soc']}% load {bat['load_w']} W {step.slot.price:.2f}p → {position}"
        f"{' (' + record['buying'] + ')' if 'buying' in record else ''} sent={record.get('applied', {}).get('sent')}",
        flush=True,
    )
    return step.action == "buy"


async def run(cfg, battery, dry_run, once=False):
    out = Path(cfg["output"]["dir"])
    state = State(out / "state.json")
    lm = loads.Loads(out, switch_names(cfg))
    learned = learner(cfg, battery)
    while True:
        fast = False
        for attempt in range(RETRIES + 1):
            try:
                fast = await asyncio.to_thread(
                    cycle, cfg, battery, state, lm, learned, dry_run
                )
                break
            except Exception as e:
                print(
                    f"{datetime.now().astimezone():%H:%M:%S} cycle failed (attempt {attempt + 1}): {e!r}",
                    flush=True,
                )
                with open(out / "log.jsonl", "a") as f:
                    f.write(
                        json.dumps(
                            {
                                "t": datetime.now(timezone.utc).isoformat(),
                                "error": repr(e),
                            }
                        )
                        + "\n"
                    )
                if attempt < RETRIES:
                    await asyncio.sleep(RETRY_DELAY)
        if once:
            return
        period = (BUYING_CYCLE if fast else CYCLE).total_seconds()
        await asyncio.sleep(period - time.time() % period + 15)


def plan_cmd(cfg, battery, soc, load, curve_path):
    """Print the plan; reads the battery only if no SoC is given, and never records history or takes a position."""
    if curve_path:
        battery = dataclasses.replace(battery, curve=Curve.load(curve_path))
    if soc is None:
        soc = call(cfg, "battery")["soc"]
    now = datetime.now(timezone.utc)
    published = fetch_rates(cfg, now - timedelta(minutes=30))
    free = free_windows(cfg, {}, {})
    rates = make_free(published, free)
    slots = slots_from(rates, now)
    terminal = optimise.terminal_value(slots_from(published, now))
    if load is None:
        lm = loads.Loads(cfg["output"]["dir"], switch_names(cfg))
        model = lm.model(
            now, lambda since: make_free(fetch_rates(cfg, since), free)
        )
        scenarios, info = lm.scenarios(now, slots, rates, model)
        print(json.dumps(info))
    else:
        scenarios = [[load] * len(slots)]
    steps, info = stochastic.plan(slots, soc, scenarios, battery, terminal)
    mean_w = [sum(col) / len(col) for col in zip(*scenarios)]
    print(json.dumps(info))
    print(render(steps, slots, soc, mean_w, terminal, info))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    sub = p.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("plan")
    pp.add_argument("--soc", type=float)
    pp.add_argument("--load", type=float)
    pp.add_argument("--curve")
    pr = sub.add_parser("run")
    pr.add_argument("--dry-run", action="store_true")
    pr.add_argument("--once", action="store_true")
    args = p.parse_args()
    cfg, battery = load_config(args.config)
    Path(cfg["output"]["dir"]).mkdir(parents=True, exist_ok=True)
    if args.cmd == "plan":
        plan_cmd(cfg, battery, args.soc, args.load, args.curve)
    else:
        asyncio.run(run(cfg, battery, args.dry_run, args.once))


if __name__ == "__main__":
    sys.exit(main())
