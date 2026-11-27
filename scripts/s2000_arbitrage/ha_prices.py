"""Print the account's unit rates as JSON ``[[start, end, p/kWh inc VAT], ...]``.

    ha_prices.py --config FILE --from 2026-11-24T00:00:00+00:00

Reads ``[home_assistant] url, token, current_rates, next_rates, rate_sensor``:
the Octopus Energy integration's current and next day rates entities and its
current rate sensor, which follow whatever tariff the meter is on.

Each slot is priced as it stood when the slot began: the integration rewrites
today's rates when the tariff changes, but past slots should keep the price
that applied then. Half-hourly rates come from the current day entity's state
history; older than that, from the rate sensor's hourly means in the
recorder's long-term statistics.
"""

import argparse
import json
from datetime import datetime, timezone

import config
import homeassistant


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument(
        "--from", dest="since", required=True, type=datetime.fromisoformat
    )
    args = p.parse_args()
    ha = config.load(args.config)["home_assistant"]
    url, token = ha["url"], ha["token"]

    now = datetime.now(timezone.utc)
    states = [
        *homeassistant.attribute_history(
            url, token, ha["current_rates"], args.since, now
        ),
        *(
            (now, homeassistant.attributes(url, token, e))
            for e in (ha["current_rates"], ha["next_rates"])
        ),
    ]
    seen = {}
    for changed, attributes in sorted(states, key=lambda s: s[0]):
        for r in attributes.get("rates") or []:
            start = datetime.fromisoformat(r["start"])
            seen.setdefault(start, []).append(
                (changed, datetime.fromisoformat(r["end"]), r["value_inc_vat"])
            )
    rates = []
    for start, versions in seen.items():
        known = [v for v in versions if v[0] <= start]
        _, end, price = known[-1] if known else versions[0]
        rates.append((start, end, price))

    first = min((r[0] for r in rates), default=now)
    if args.since < first:
        rates += homeassistant.hourly_means(
            url, token, ha["rate_sensor"], args.since, first
        )

    out = [
        [s.isoformat(), e.isoformat(), round(price * 100, 4)]
        for s, e, price in sorted(rates)
        if e > args.since
    ]
    print(json.dumps(out))


if __name__ == "__main__":
    main()
