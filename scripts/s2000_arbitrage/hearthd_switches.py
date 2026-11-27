"""Print hearthd on/off nodes as JSON ``{name: true | false | null}``.

    hearthd_switches.py --url https://hearthd.example NAME...

Each NAME is a hearthd alias or node name. null means the node or its OnOff state is missing.
"""

import argparse
import json
import urllib.request


def on_off(node):
    for endpoint in node["endpoints"].values():
        cluster = endpoint["clusters"].get("OnOff")
        if cluster:
            return cluster["on_off"]
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("names", nargs="*")
    args = p.parse_args()
    with urllib.request.urlopen(f"{args.url}/v1/state", timeout=60) as resp:
        state = json.load(resp)
    out = {}
    for name in args.names:
        ids = (
            [state["aliases"][name]]
            if name in state["aliases"]
            else state["names"].get(name, [])
        )
        node = state["nodes"].get(ids[0]) if len(ids) == 1 else None
        out[name] = on_off(node) if node else None
    print(json.dumps(out))


if __name__ == "__main__":
    main()
