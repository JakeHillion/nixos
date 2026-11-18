"""Applies port configuration to a UniFi switch through its controller.

Reads the desired state rendered from the network registry, diffs it against
the port settings the controller holds for the switch and writes the port
overrides that close the gap.
"""

import argparse
import copy
import http.cookiejar
import json
import sys
import urllib.request


class Controller:
    def __init__(self, url, user, password):
        self.url = url
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
        )
        self.csrf = None
        self.request(
            "POST",
            "/api/auth/login",
            {"username": user, "password": password},
        )

    def request(self, method, path, body=None):
        request = urllib.request.Request(
            self.url + path,
            method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
        )
        if self.csrf:
            request.add_header("X-CSRF-Token", self.csrf)
        with self.opener.open(request, timeout=30) as response:
            self.csrf = response.headers.get("X-CSRF-Token", self.csrf)
            return json.load(response)

    def network(self, method, path, body=None):
        return self.request(method, f"/proxy/network/api{path}", body)["data"]


def port_settings(port, default):
    """The settings of a port that this script manages, in one shape."""
    mode = port.get("tagged_vlan_mgmt") or "auto"
    return {
        "name": port.get("name"),
        "native_networkconf_id": port.get("native_networkconf_id") or default,
        "tagged_vlan_mgmt": mode,
        "excluded_networkconf_ids": (
            sorted(port.get("excluded_networkconf_ids") or [])
            if mode == "custom"
            else []
        ),
    }


def wanted_settings(number, want, have, networks, default):
    """The settings the registry asks of a port, as the controller words them.

    A VLAN-only network carries the VLAN ID the registry knows it by. The
    controller's default network is untagged, which is VLAN 1.
    """
    by_vlan = {
        network.get("vlan") or 1: network["_id"] for network in networks
    }

    def network_id(vlan):
        if vlan not in by_vlan:
            sys.exit(f"port {number}: the controller has no VLAN {vlan}")
        return by_vlan[vlan]

    if want["native"] is None:
        sys.exit(f"port {number}: a UniFi port needs a native network")
    native = network_id(want["native"])

    if want["tagged"] == "all":
        mode, excluded = "auto", []
    elif not want["tagged"]:
        mode, excluded = "block_all", []
    else:
        mode = "custom"
        tagged = {network_id(vlan) for vlan in want["tagged"]}
        excluded = sorted(set(by_vlan.values()) - tagged - {native})

    return {
        "name": want["description"] or have["name"],
        "native_networkconf_id": native,
        "tagged_vlan_mgmt": mode,
        "excluded_networkconf_ids": excluded,
    }


def diff(state, device, networks):
    """Returns the port overrides to write, or None if nothing changes."""
    default = next(n["_id"] for n in networks if not n.get("vlan"))
    table = {str(port["port_idx"]): port for port in device["port_table"]}
    overrides = copy.deepcopy(device.get("port_overrides") or [])

    changed = False
    for number, want in sorted(
        state["ports"].items(), key=lambda p: int(p[0])
    ):
        if number not in table:
            sys.exit(f"{device['name']} has no port {number}")
        have = port_settings(table[number], default)
        wanted = wanted_settings(number, want, have, networks, default)
        if wanted == have:
            continue
        changed = True
        print(f"port {number}: {json.dumps(have)} -> {json.dumps(wanted)}")

        override = next(
            (o for o in overrides if str(o["port_idx"]) == number), None
        )
        if override is None:
            override = {"port_idx": int(number)}
            overrides.append(override)
        override.update(wanted)
        # The controller keeps a coarser summary of the same choice.
        override["forward"] = {
            "auto": (
                "all"
                if wanted["native_networkconf_id"] == default
                else "customize"
            ),
            "block_all": "native",
            "custom": "customize",
        }[wanted["tagged_vlan_mgmt"]]

    return overrides if changed else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state", help="desired state, as JSON")
    parser.add_argument("--password-file", required=True)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the changes that would be made and change nothing",
    )
    args = parser.parse_args()

    with open(args.state) as f:
        state = json.load(f)
    with open(args.password_file) as f:
        password = f.read().strip()

    controller = Controller(state["controller"], state["user"], password)
    sites = controller.network("GET", "/self/sites")
    site = next(s["name"] for s in sites if s["desc"] == state["site"])

    def read():
        devices = controller.network("GET", f"/s/{site}/stat/device")
        device = next(d for d in devices if d["mac"] == state["mac"])
        networks = controller.network("GET", f"/s/{site}/rest/networkconf")
        return device, networks

    device, networks = read()
    overrides = diff(state, device, networks)
    if overrides is None:
        print(f"{device['name']}: up to date")
        return
    if args.dry_run:
        return

    controller.network(
        "PUT",
        f"/s/{site}/rest/device/{device['_id']}",
        {"port_overrides": overrides},
    )
    if diff(state, *read()) is not None:
        sys.exit("the controller did not take these changes")
    print(f"{device['name']}: applied")


if __name__ == "__main__":
    main()
