"""Print joined free-electricity windows from Home Assistant as JSON ``[[start, end], ...]``.

    ha_free.py --config FILE

Reads ``[home_assistant] url, token, free_events``: the Octopus Energy
integration's Octoplus power-up events entity, whose ``events`` attribute lists
the weekend happy hours and power-ups the account has joined.
"""

import argparse
import json

import config
import homeassistant


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    args = p.parse_args()
    ha = config.load(args.config)["home_assistant"]
    events = homeassistant.attributes(
        ha["url"], ha["token"], ha["free_events"]
    )["events"]
    print(json.dumps(sorted([e["start"], e["end"]] for e in events)))


if __name__ == "__main__":
    main()
