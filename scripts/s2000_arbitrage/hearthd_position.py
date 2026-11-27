"""Put the S2000 in a trading position through hearthd and print what was sent, as JSON.

    hearthd_position.py --config FILE buy|sell|hold

- buy: pass-through and charging at ``[device] buy_limit_w``.
- sell: the battery carries the load down to ``[device] floor_soc``.
- hold: self-consumption with the reserve at the current charge, so the grid carries the load.

hearthd only passes on settings that differ, so repeating a position is
harmless. The reserve is set before the mode so a mode change never runs the
battery below it. The AC output is never touched.
"""

import argparse
import json

import config
import hearthd


def wanted(position, soc, floor, buy_w):
    if position == "buy":
        return {
            "reserve": floor,
            "charge_power_limit": buy_w * 1000,
            "mode": hearthd.MODE_PASSTHROUGH,
        }
    if position == "sell":
        return {"reserve": floor, "mode": hearthd.MODE_SELF_CONSUMPTION}
    return {"reserve": max(floor, soc), "mode": hearthd.MODE_SELF_CONSUMPTION}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument("position", choices=("buy", "sell", "hold"))
    args = p.parse_args()
    d = config.load(args.config)["device"]
    url, node = d["url"], d["node"]
    soc = None
    if args.position == "hold":
        soc = hearthd.battery(hearthd.endpoints(url, node))["soc"]
    want = wanted(args.position, soc, d["floor_soc"], d["buy_limit_w"])
    for attribute, value in want.items():
        if attribute == "mode":
            hearthd.set_mode(url, node, value)
        else:
            hearthd.set_setting(url, node, attribute, value)
    print(json.dumps({"soc": soc, "sent": want}))


if __name__ == "__main__":
    main()
