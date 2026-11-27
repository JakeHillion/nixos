"""The S2000 as hearthd exposes it: Matter clusters on one node.

Reads ``[device]``: ``url`` is hearthd's base URL, ``node`` the S2000's alias or
name. Powers are in mW, positive into the device; SoC in half-percent.
"""

import json
import urllib.request

BATTERY = "1"
AC_OUTPUT = "2"
GRID_INPUT = "3"
SETTINGS = 7

MODE_PASSTHROUGH = 0
MODE_SELF_CONSUMPTION = 2


def endpoints(url, node):
    with urllib.request.urlopen(f"{url}/v1/state", timeout=60) as resp:
        state = json.load(resp)
    ids = (
        [state["aliases"][node]]
        if node in state["aliases"]
        else state["names"].get(node, [])
    )
    if len(ids) != 1:
        raise LookupError(f"hearthd has {len(ids)} nodes named {node}")
    return state["nodes"][ids[0]]["endpoints"]


def battery(eps):
    """The battery's state in the controller's units: percent, W, and the S2000's own mode numbers."""
    power = lambda ep: eps[ep]["clusters"]["ElectricalPowerMeasurement"][
        "active_power"
    ]
    settings = eps[str(SETTINGS)]["clusters"]
    out = {
        "soc": eps[BATTERY]["clusters"]["PowerSource"][
            "bat_percent_remaining"
        ],
        "load_w": power(AC_OUTPUT),
        "grid_w": power(GRID_INPUT),
        "ac_on": eps[AC_OUTPUT]["clusters"]["OnOff"]["on_off"],
        "mode": settings["ModeSelect"]["current_mode"],
        "backup_soc": settings["BatteryStorageControl"]["reserve"],
        "charge_limit_w": settings["BatteryStorageControl"][
            "charge_power_limit"
        ],
    }
    missing = [k for k, v in out.items() if v is None]
    if missing:
        raise ValueError(
            f"hearthd has no {', '.join(missing)} for the S2000 yet"
        )
    out["soc"] //= 2
    out["load_w"] = -out["load_w"] // 1000
    out["grid_w"] //= 1000
    out["charge_limit_w"] //= 1000
    return out


def _post(url, node, kind, body):
    req = urllib.request.Request(
        f"{url}/v1/nodes/{node}/{kind}",
        data=json.dumps({"endpoint": SETTINGS, **body}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def set_setting(url, node, attribute, value):
    _post(
        url,
        node,
        "write",
        {
            "write": {
                "cluster": "BatteryStorageControl",
                "attribute": attribute,
                "value": value,
            }
        },
    )


def set_mode(url, node, mode):
    _post(
        url,
        node,
        "command",
        {
            "command": {
                "cluster": "ModeSelect",
                "command": {"ChangeToMode": {"new_mode": mode}},
            }
        },
    )
