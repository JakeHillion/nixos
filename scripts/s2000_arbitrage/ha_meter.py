"""Print the grid-side plug meter as JSON ``{"power": [W, updated], "energy": [kWh, updated]}``.

    ha_meter.py --config FILE

Reads ``[home_assistant] url, token, power_entity, energy_entity``.
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
    print(
        json.dumps(
            {
                "power": homeassistant.read(
                    ha["url"], ha["token"], ha["power_entity"]
                ),
                "energy": homeassistant.read(
                    ha["url"], ha["token"], ha["energy_entity"]
                ),
            }
        )
    )


if __name__ == "__main__":
    main()
