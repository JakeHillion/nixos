"""Applies VLAN and port configuration to an EdgeSwitch over its SSH CLI.

Reads the desired state rendered from the network registry, diffs it against
the switch's running config and sends the commands that close the gap. The
running config is only saved once the switch and the gateway are still
reachable through it, so power-cycling the switch undoes a change that cuts
this host off.
"""

import argparse
import json
import re
import subprocess
import sys

PROMPT = re.compile(r"^\(.*\) [>#]")


def expand(spec):
    """Expands a VLAN list such as "2,4-7" into a set of IDs."""
    ids = set()
    for part in spec.split(","):
        first, _, last = part.partition("-")
        ids.update(range(int(first), int(last or first) + 1))
    return ids


def run(state, password_file, commands):
    """Runs CLI commands in privileged exec mode and returns the output."""
    with open(password_file) as f:
        password = f.read().strip()
    result = subprocess.run(
        [
            "sshpass",
            "-f",
            password_file,
            "ssh",
            "-T",
            "-o",
            "LogLevel=ERROR",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "PubkeyAuthentication=no",
            "-o",
            "ConnectTimeout=10",
            f"{state['user']}@{state['address']}",
        ],
        input="\n".join(
            ["enable", password, "terminal length 0", *commands, ""]
        ),
        capture_output=True,
        text=True,
        timeout=120,
    )
    if "#terminal length 0" not in result.stdout:
        sys.exit(
            f"could not reach privileged exec mode on {state['address']}:\n"
            f"{result.stdout}{result.stderr}"
        )
    return result.stdout


def running_config(state, password_file):
    """Reads the VLAN database and each port's VLAN settings."""
    output = run(state, password_file, ["show running-config"])
    lines = output.split("#show running-config", 1)[1].splitlines()

    vlans = {1}
    ports = {}
    port = None
    for line in map(str.strip, lines):
        if PROMPT.match(line):
            break
        if match := re.fullmatch(r"vlan ([\d,-]+)", line):
            vlans |= expand(match[1])
        elif match := re.fullmatch(r"interface +0/(\d+)", line):
            port = ports[match[1]] = {
                "description": None,
                "pvid": 1,
                "include": set(),
                "exclude": set(),
                "tagging": set(),
            }
        elif line == "exit":
            port = None
        elif port is None:
            continue
        elif match := re.fullmatch(r"description '(.*)'", line):
            port["description"] = match[1]
        elif match := re.fullmatch(r"vlan pvid (\d+)", line):
            port["pvid"] = int(match[1])
        elif match := re.fullmatch(
            r"vlan participation (include|exclude) ([\d,-]+)", line
        ):
            port[match[1]] |= expand(match[2])
        elif match := re.fullmatch(r"vlan tagging ([\d,-]+)", line):
            port["tagging"] |= expand(match[1])
    return vlans, ports


def is_member(port, vlan):
    # Every port is in the default VLAN unless excluded. Other VLANs need an
    # explicit include.
    if vlan == 1:
        return vlan not in port["exclude"]
    return vlan in port["include"]


def diff(state, vlans, ports):
    """Returns the commands that bring the switch to the desired state."""
    wanted_vlans = {int(vlan): name for vlan, name in state["vlans"].items()}
    commands = []

    missing = sorted(set(wanted_vlans) - vlans)
    if missing:
        commands.append("vlan database")
        for vlan in missing:
            commands.append(f"vlan {vlan}")
            commands.append(f'vlan name {vlan} "{wanted_vlans[vlan]}"')
        commands.append("exit")

    interfaces = []
    for number, want in sorted(
        state["ports"].items(), key=lambda p: int(p[0])
    ):
        if number not in ports:
            sys.exit(f"{state['address']} has no port 0/{number}")
        have = ports[number]
        native = want["native"]
        if want["tagged"] == "all":
            tagged = set(wanted_vlans) - {native}
        else:
            tagged = set(want["tagged"])

        changes = []
        if want["description"] not in (None, have["description"]):
            changes.append(f"description '{want['description']}'")
        # Join VLANs and move the PVID before leaving any, so the port is
        # never left without its native VLAN.
        for vlan in sorted(tagged | {native} - {None}):
            if not is_member(have, vlan):
                changes.append(f"vlan participation include {vlan}")
            if vlan in tagged and vlan not in have["tagging"]:
                changes.append(f"vlan tagging {vlan}")
            if vlan == native and vlan in have["tagging"]:
                changes.append(f"no vlan tagging {vlan}")
        if native is not None and have["pvid"] != native:
            changes.append(f"vlan pvid {native}")
        for vlan in sorted((vlans | set(wanted_vlans)) - tagged - {native}):
            if is_member(have, vlan):
                changes.append(f"vlan participation exclude {vlan}")

        if changes:
            interfaces += [f"interface 0/{number}", *changes, "exit"]

    if interfaces:
        commands += ["configure", *interfaces, "exit"]
    return commands


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state", help="desired state, as JSON")
    parser.add_argument("--password-file", required=True)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the commands that would be sent and change nothing",
    )
    args = parser.parse_args()

    with open(args.state) as f:
        state = json.load(f)

    commands = diff(state, *running_config(state, args.password_file))
    if not commands:
        print(f"{state['address']}: up to date")
        return
    print("\n".join(commands))
    if args.dry_run:
        return

    run(state, args.password_file, commands)

    # Both checks go through the new config: a fresh session to the switch,
    # and a ping to the gateway beyond it.
    remaining = diff(state, *running_config(state, args.password_file))
    if remaining:
        sys.exit(
            "the switch did not take these commands, not saving:\n"
            + "\n".join(remaining)
        )
    ping = subprocess.run(
        ["ping", "-c", "3", "-W", "2", state["gateway"]],
        capture_output=True,
    )
    if ping.returncode != 0:
        sys.exit(f"{state['gateway']} is unreachable, not saving")

    output = run(state, args.password_file, ["write memory", "y"])
    if "Configuration Saved!" not in output:
        sys.exit(f"saving the config failed:\n{output}")
    print(f"{state['address']}: applied and saved")


if __name__ == "__main__":
    main()
