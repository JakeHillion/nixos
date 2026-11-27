"""Print the S2000's state from hearthd as JSON.

    hearthd_battery.py --config FILE

``load_w`` is the AC output and ``grid_w`` the AC input.
"""

import argparse
import json

import config
import hearthd


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    args = p.parse_args()
    d = config.load(args.config)["device"]
    print(json.dumps(hearthd.battery(hearthd.endpoints(d["url"], d["node"]))))


if __name__ == "__main__":
    main()
