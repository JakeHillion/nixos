---
name: commit
description: Use when writing commit messages, describing changes, or preparing commits.
---

# Commit Message Guidelines

**If the repository has its own commit message guidelines (in CLAUDE.md, CONTRIBUTING.md, or similar), follow those instead of this skill.**

**Claude is commonly used in repositories with Jujutsu instead of Git. If this repository has a `.jj` directory, use `jj commit -m '...'` to commit instead of `git commit -m '...'`.**

## Format

### Subject line

```
AREA: what changed (one line)
```

`AREA` is the most specific component affected:
- Host name (e.g. `bob`, `cyclone`, `phoenix`)
- Module name (e.g. `router`, `topology`, `impermanence`)
- Service name (e.g. `gitea`, `restic`, `jellyfin`)
- Tool/config area (e.g. `zsh`, `neovim`, `claude`)

If the change spans multiple areas, use the most specific shared area.

Examples:
```
router: add NAT loopback support for port forwarding
bob: connect to Aspire Guest wifi
topology: fix VLAN interface naming for IoT network
```

### Body

Write the body as short prose:

- 1-3 sentences describing the **issue or behaviour** this commit addresses.
- 1-3 sentences describing **how** the change was implemented.
- 1-2 sentences explaining **why** this implementation solves the issue.

### Test plan

Every commit message ends with a `Test plan:` block:

```
Test plan:
- Built configuration with `nix build '.#nixosConfigurations."host.domain".config.system.build.toplevel'`
- Deployed and verified <specific behaviour>
- Checked <relevant service/feature> works correctly
```

## One-commit rule

This repository follows a **one commit per branch / one commit per PR** policy.

- Do not create fixup commits or iterative commits.
- **Amend** the single commit as work evolves using `jj squash`.
- Before pushing, ensure the commit contains the final, polished message.

## Example

```
router: add NAT loopback for internal access via WAN IP

Internal clients couldn't access services using the external WAN IP
because packets destined for the WAN IP were being dropped by the
firewall when originating from internal networks.

Added NAT loopback rules to the nftables configuration that DNAT
packets from internal networks destined for the WAN IP back to the
appropriate internal server, then SNAT the return path so responses
route correctly.

This allows internal clients to use the same external URLs as external
clients, simplifying DNS configuration and service discovery.

Test plan:
- Built router configuration successfully
- Verified internal client can reach service via WAN IP
- Confirmed external access still works
```
