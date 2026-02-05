# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Test configuration for a specific host
nix build '.#nixosConfigurations."hostname.domain.tld".config.system.build.toplevel'

# Format code (required before committing)
nix fmt

# Run all checks (linting + tests)
nix flake check --all-systems

# Build Raspberry Pi SD card image
nix build '.#nixosConfigurations."li.pop.neb.jakehillion.me".config.formats.sd-aarch64'

# Regenerate test snapshots
nix run .#generate-snapshots

# Build closure and transfer to slow host
STORE_PATH=$(nix build --no-link --print-out-paths '.#nixosConfigurations."boron.cx.neb.jakehillion.me".config.system.build.toplevel')
nix-store --export $(nix-store --query --requisites $STORE_PATH) | zstd > closure.nar.zst
cat closure.nar.zst | ssh boron.cx.neb.jakehillion.me sh -c 'unzstd | sudo nix-store --import'
```

## Project Structure

- `/hosts/` - Host-specific configurations (17 hosts, each in `<fqdn>/default.nix`)
- `/modules/` - Reusable NixOS modules (networking, services, www, etc.)
- `/models/` - Hardware configuration templates (8 models for different hardware)
- `/lib/` - Shared Nix utilities (`mkSystem.nix` for host composition)
- `/pkgs/` - Custom package definitions
- `/secrets/` - Encrypted secrets via agenix
- `/scripts/` - Utility scripts
- `/tests/` - Module tests with snapshot verification

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
   };
   ```

Key design decisions:
- One router per location (defined as `routerDevice` at location level)
- Gateway addresses are always .1 in each subnet (e.g., 10.0.0.1 for 10.0.0.0/24)
- VLANs are supported via the `vlanId` parameter
- DHCP is configured automatically for networks with `dhcpEnabled = true`
- Router firewall (nftables) is configured based on the topology
- Networks can be configured with or without internet access
- Port forwarding and router services are configurable in the topology
- Port forwarding rules can reference devices by FQDN instead of IP address
- NAT loopback/reflection allows internal clients to access services via external WAN IP (configurable per port forwarding rule)

Example topology configuration:
```nix
custom.topology = {
  home = {
    description = "Home Network";
    routerDevice = "router.home.example.com";
    wanInterface = "eth0";
    networks = {
      lan = {
        subnet = "10.0.0.0/24";
        interface = "eth1";
        dhcpEnabled = true;
        dhcpPool = { start = "10.0.0.64"; end = "10.0.0.254"; };
        reservedIps = {
          "20" = {
            hostname = "desktop";
            fqdn = "desktop.example.com";
            hwAddress = "00:11:22:33:44:66";
            dhcpReservation = true;
          };
        };
        internetAccess = true;
        trustedNetwork = true;
      };
      iot = {
        vlanId = 10;
        subnet = "10.0.10.0/24";
        interface = "eth1";
        internetAccess = true;
        trustedNetwork = false;
      };
    };
  };
};
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
- Port forwarding rules can reference devices by FQDN (resolved from `reservedIps`)

### Secret Management

Secrets are managed with agenix. Place module-specific secrets (API keys, SSH keys) next to the module that uses them. Generic secrets (like Restic shared passwords) go in `/secrets/`.

## Coding Conventions

- **Avoid global `with lib;`**: Use fully qualified names (e.g., `lib.mkOption`, `lib.strings.concatStringsSep`)
- **Format before commit**: Always run `nix fmt` before committing

## Service Configuration and Management

### Service Orchestration with locations.autoServe

The repository uses a centralized service orchestration system through `modules/locations.nix` that automatically deploys services to designated hosts.

#### How locations.autoServe Works

1. **Service Registry**: `modules/locations.nix` maintains a mapping of services to their host locations:
   ```nix
   services = {
     attic = "phoenix.st.neb.jakehillion.me";
     gitea = "boron.cx.neb.jakehillion.me";
     restic = "phoenix.st.neb.jakehillion.me";
     # Services can also run on multiple hosts
     authoritative_dns = [
       "boron.cx.neb.jakehillion.me"
       "router.home.neb.jakehillion.me"
     ];
   };
   ```

2. **Automatic Service Activation**: When `custom.locations.autoServe = true` is enabled on a host:
   - The system compares `config.networking.fqdn` against the service mappings
   - Services assigned to that host are automatically enabled
   - Enabled by default in `modules/defaults.nix`

3. **Service Discovery**: Other services can reference locations via:
   ```nix
   config.custom.locations.locations.services.servicename
   ```

#### Service Configuration Patterns

All service modules follow a consistent pattern in `/modules/services/`:

```nix
{ config, lib, ... }:
let
  cfg = config.custom.services.servicename;
in
{
  options.custom.services.servicename = {
    enable = lib.mkEnableOption "servicename";
    # service-specific options
  };
  
  config = lib.mkIf cfg.enable {
    # service configuration
  };
}
```

#### World-Accessible vs Internal Services

**World-Accessible Services** (using `custom.www.global.enable = true`):
- Managed by `modules/www/global.nix`
- Use Cloudflare integration and ACME certificates
- Examples: Gitea, blog, PrivateBin, Matrix
- Exposed via public domains like `*.hillion.co.uk`

**Internal Services** (using `custom.www.nebula.enable = true`):
- Managed by `modules/www/nebula.nix`
- Accessible only via Nebula VPN network
- Use internal CA for TLS certificates
- Examples: Restic, Downloads, internal tools

#### Adding a New Service

1. **Create the service module** in `/modules/services/servicename.nix`
2. **Add to locations.nix**:
   ```nix
   services = {
     # ... existing services
     servicename = "hostname.domain.tld";
   };
   ```
3. **Configure web access** (if needed):
   - For world access: Enable `custom.www.global.enable = true`
   - For internal access: Enable `custom.www.nebula.enable = true`
4. **Add backup configuration** (if needed) with restic integration

#### Service Integration Points

- **Secrets**: Use agenix for secret management (`/secrets/` directory)
- **Reverse Proxy**: Caddy handles internal routing and SSL termination
- **Systemd**: Custom service definitions and timers
- **Firewall**: Services automatically configure required ports
- **Backup**: Many services integrate with restic backup system
- **User Management**: Consistent UID/GID allocation via `config.ids`
- **Impermanence**: Configure persistent storage paths for service data

#### Impermanence Configuration

For systems using impermanence (ephemeral root filesystem), service data must be explicitly persisted. The repository uses two patterns:

**Pattern 1: Override service data directories (Preferred)**
```nix
# In modules/impermanence.nix
services.matrix-synapse.dataDir = "${cfg.base}/system/var/lib/matrix-synapse";
services.gitea.stateDir = "${cfg.base}/system/var/lib/gitea";
services.jellyfin.dataDir = "${cfg.base}/services/jellyfin";
```

**Pattern 2: Add directories to impermanence bind mounts (Fallback)**
```nix
# In modules/impermanence.nix - directories array
(lib.lists.optional config.services.zigbee2mqtt.enable config.services.zigbee2mqtt.dataDir)
(lib.lists.optional config.custom.services.unifi.enable "/var/lib/unifi")
```

**IMPORTANT**: Every new service that stores data must be configured for impermanence using Pattern 1 when possible. Services without configurable data directories fall back to Pattern 2.

**Adding a new service with impermanence:**
1. Check if the service has a configurable data directory option
2. If yes, override it to point to `${cfg.base}/system/var/lib/servicename` or `${cfg.base}/services/servicename`
3. If no, add the default data directory to the impermanence directories list
4. Use conditional configuration with `lib.mkIf config.services.servicename.enable`

## Git Workflow

This repository uses **Jujutsu (jj)** and follows a **single-commit-per-change** workflow:

- Every pull request must have exactly 1 commit with a `change-id` header (added automatically by jj)
- Use `jj amend` instead of creating fix commits
- CI validates single-commit requirement and change-id presence

```bash
# Make changes and commit with jj
jj commit -m "feat: add new service"

# Need to fix something? Amend instead of new commit
jj amend
```

## Important: Nix and Git Integration

When adding new files, you must run `git add <file>` before Nix commands will recognize them. Nix evaluates based on the git index, not the filesystem.

- Always use `git add <specific-file>` for new files
- Never run `git add .`
- Don't commit changes without being asked