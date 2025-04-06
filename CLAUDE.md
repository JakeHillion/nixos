# NixOS Configuration Guide for Claude

This document provides guidance for Claude AI when working with this NixOS configuration.

## Project Structure

- `/hosts/` - Host-specific configurations
- `/modules/` - Reusable NixOS modules
- `/models/` - Hardware configuration modules
- `/secrets/` - Encrypted secrets (via agenix)
- `/scripts/` - Utility scripts

## Key Modules and Abstractions

### Network Topology and Router Configuration

The network configuration is abstracted in:
- `modules/topology.nix` - Defines network layout and properties
- `modules/router.nix` - Implements router functionality

To configure a new router:

1. Add the host entry to the corresponding location in `modules/topology.nix`
2. Enable the router module in the host configuration:
   ```nix
   custom.router = {
     auto = true;
     location = "home"; # or other location name
   };
   ```

Key design decisions:
- One router per location (defined as `routerDevice` at location level)
- Gateway addresses are always .1 in each subnet (e.g., 10.0.0.1 for 10.0.0.0/24)
- VLANs are supported via the `vlanId` parameter

### Testing Configuration Changes

To validate configuration changes for a specific host, use:

```bash
nix build '.#nixosConfigurations."hostname.domain.tld".config.system.build.toplevel'
```

For example:
```bash
nix build '.#nixosConfigurations."cyclone.gw.neb.jakehillion.me".config.system.build.toplevel'
```

## Common Tasks

### Adding a New Host

1. Create a directory under `/hosts/<fqdn>/`
2. Add a `default.nix` with the host configuration
3. Create a `system` file with the architecture (e.g., `x86_64-linux`)
4. If needed, add a `hardware-configuration.nix` file

### Networking Conventions

- Home network uses 10.x.x.x subnets
- Gateway is always .1 in each subnet
- DHCP ranges typically start at .64 and end at .254

### Secret Management

Secrets are managed with agenix and stored in the `/secrets/` directory.

## Coding Conventions

- **Avoid global `with lib;`**: Never use global `with lib;` statements in modules. Instead, use fully qualified names (e.g., `lib.mkOption`, `lib.strings.concatStringsSep`, etc.). This improves code readability and avoids namespace conflicts.

## Common Errors and Solutions

- **FQDN comparison issues**: When comparing hostnames, use the full FQDN
- **VLAN interface errors**: Make sure parent interfaces are correctly defined

## Development Workflow

1. Make changes to configuration
2. Test with `nix build` for specific host
3. Commit changes
4. Apply on target system with `nixos-rebuild switch`