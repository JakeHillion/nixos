"""Print Home Assistant on/off entities as JSON ``{entity: true | false | null}``.

    ha_switches.py --config FILE ENTITY...

Reads ``[home_assistant] url, token``. null means unavailable.
"""

import argparse
import json

import config
import homeassistant


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument("entities", nargs="*")
    args = p.parse_args()
    ha = config.load(args.config)["home_assistant"]
    print(
        json.dumps(
            {
                e: homeassistant.is_on(ha["url"], ha["token"], e)
                for e in args.entities
            }
        )
    )


if __name__ == "__main__":
    main()
