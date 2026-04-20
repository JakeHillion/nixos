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

- `/hosts/` - Host-specific configurations (18 hosts, each in `<fqdn>/default.nix`)
- `/modules/` - Reusable NixOS modules (networking, services, www, etc.)
  - `/modules/networking/` - Network topology, router, and DHCP configuration
- `/models/` - Hardware configuration templates (8 models for different hardware)
- `/lib/` - Shared Nix utilities (`mkSystem.nix` for host composition)
- `/pkgs/` - Custom package definitions
- `/secrets/` - Encrypted secrets via agenix
- `/scripts/` - Utility scripts
- `/tests/` - Module tests with snapshot verification

## Ogygia and Domain Configuration

This repository follows [ogygia-nix](https://github.com/JakeHillion/ogygia-nix) methodologies. Ogygia provides fleet coordination, configuration revision tracking, and peer-to-peer binary caching (irisd).

The key option is `config.ogygia.domain` which resolves to `"neb.jakehillion.me"` and is used in **47+ files** for constructing host FQDNs. Host names in the codebase use the pattern `<name>.<location>.${config.ogygia.domain}` (e.g., `boron.cx.${config.ogygia.domain}` → `boron.cx.neb.jakehillion.me`). Never hardcode the domain — always use `config.ogygia.domain`.

The `custom.ogygia.enable` option (enabled by default in `modules/defaults.nix`) wraps the upstream ogygia module, configuring domain, git remote, nebula, irisd, and etcd integration.

## Key Modules and Abstractions

### Network Topology and Router Configuration

The network configuration is abstracted in:
- `modules/networking/topology.nix` - Defines network layout and properties
- `modules/networking/router.nix` - Implements router functionality

To configure a new router:

1. Add the host entry to the corresponding location in `modules/networking/topology.nix`
2. Enable the router module in the host configuration:
   ```nix
   custom.networking.router = {
     auto = true;
   };
   ```

Key design decisions:
- One router per location (defined as `routerDevice` at location level)
- Gateway addresses are always .1 in each subnet (e.g., 10.0.0.1 for 10.0.0.0/24)
- DHCP is configured automatically for networks with `dhcpEnabled = true`
- Router firewall (nftables) is configured based on the topology
- Port forwarding rules can reference devices by FQDN instead of IP address (resolved from the `devices` attribute in each network)

Read `modules/networking/topology.nix` and `modules/networking/router.nix` directly when making changes — they contain the full schema with all available options (DNS servers, NTP servers, VLANs, WAN MAC/IP, port forwarding with protocol/loopback/internalPort, etc.).

## Common Tasks

### Adding a New Host

1. Create a directory under `/hosts/<fqdn>/`
2. Add a `default.nix` with the host configuration
3. Create a `system` file with the architecture (e.g., `x86_64-linux`)
4. If needed, add a `hardware-configuration.nix` file

### Secret Management

Secrets are managed with agenix. Place module-specific secrets (API keys, SSH keys) next to the module that uses them. Generic secrets (like Restic shared passwords) go in `/secrets/`.

## Coding Conventions

- **Avoid global `with lib;`**: Use fully qualified names (e.g., `lib.mkOption`, `lib.strings.concatStringsSep`). The main codebase (modules/, hosts/, lib/) strictly follows this — only pkgs/ uses `with lib;` in meta blocks.
- **Format before commit**: Always run `nix fmt` before committing

## Service Configuration and Management

### Service Orchestration with locations.autoServe

The repository uses a centralized service orchestration system through `modules/locations.nix` that automatically deploys services to designated hosts.

#### How locations.autoServe Works

1. **Service Registry**: `modules/locations.nix` maintains a mapping of services to their host locations using `config.ogygia.domain` for FQDNs:
   ```nix
   services = {
     gitea = "boron.cx.${config.ogygia.domain}";
     restic = "phoenix.st.${config.ogygia.domain}";
     # Services can also run on multiple hosts
     authoritative_dns = [
       "boron.cx.${config.ogygia.domain}"
       "cyclone.gw.${config.ogygia.domain}"
       "slider.pop.${config.ogygia.domain}"
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

#### Web Service Architecture

The repository uses **two different architectures** for exposing services:

**World-Accessible Services** (gitea, matrix, blog, ntfy, etc.):
- `modules/www/global.nix` is a **monolithic module** that hardcodes ALL world-accessible virtual hosts in one place
- Service modules (e.g., `modules/services/gitea/`) configure ONLY the service itself — they do NOT configure their own web presence
- When `custom.www.global.enable = true` is set on a host, it creates Caddy virtual hosts that proxy to services by looking up their locations via `config.custom.locations.locations.services`
- Uses Cloudflare DNS for ACME certificates, exposed via `*.hillion.co.uk` domains

**Internal Services** (restic, downloads, privatebin, immich, etc.):
- `modules/www/nebula.nix` is a **framework** that service modules actively use
- Service modules set `custom.www.nebula.enable = true` and define their own `virtualHosts` entries
- When enabled, nebula.nix wraps virtual hosts with internal TLS and binds to the Nebula VPN IP only
- Accessible only via Nebula VPN, uses a custom ACME DNS provider (not an internal CA)

| Aspect | World-Accessible (global.nix) | Internal (nebula.nix) |
|--------|-------------------------------|-----------------------|
| Virtual hosts | Hardcoded in global.nix | Defined by each service module |
| Who enables | Set at host level | Service module sets it itself |
| TLS | Cloudflare + ACME | Custom DNS provider + ACME |
| Network | Public internet | Nebula VPN only |

#### Adding a New Service

**For an internal service** (most common):

1. **Create the service module** in `/modules/services/<name>/default.nix`:
   ```nix
   { config, lib, ... }:
   let
     cfg = config.custom.services.servicename;
   in
   {
     options.custom.services.servicename = {
       enable = lib.mkEnableOption "servicename";
     };

     config = lib.mkIf cfg.enable {
       # ... service configuration ...

       custom.www.nebula = {
         enable = true;
         virtualHosts."servicename.${config.ogygia.domain}".extraConfig = ''
           reverse_proxy http://localhost:<port>
         '';
       };
     };
   }
   ```

2. **Register in locations.nix** (so other services can discover it):
   ```nix
   services = {
     # ... existing services
     servicename = "hostname.${config.ogygia.domain}";
   };
   ```

3. **Add backup configuration** (if needed) with restic integration

**For a world-accessible service** (less common):

1. **Create the service module** in `/modules/services/<name>/default.nix` — configure the service but do NOT configure web presence
2. **Register in locations.nix** as above
3. **Add the virtual host to `modules/www/global.nix`** — add a new entry in `services.caddy.virtualHosts` that proxies to the service
4. **Add TLS certificate secrets** — place encrypted certs in `/secrets/` and reference them in the global.nix virtual host

#### Service Integration Points

- **Secrets**: Use agenix for secret management (`/secrets/` directory)
- **Reverse Proxy**: Caddy handles internal routing and SSL termination
- **Systemd**: Custom service definitions and timers
- **Firewall**: Services automatically configure required ports
- **Backup**: Many services integrate with restic backup system
- **User Management**: Consistent UID/GID allocation via `config.ids`
- **Impermanence**: Configure persistent storage paths for service data

#### Impermanence Configuration

For systems with ephemeral root filesystems, service data must be explicitly persisted. The repository uses two patterns:

**Pattern 1: Override the Service's Data Directory**

When the upstream NixOS module provides a configurable data directory option, override it in the service's module:

```nix
# In the service's module (e.g., modules/services/<name>.nix)
config = lib.mkIf cfg.enable {
  services.<service>.dataDir = lib.mkIf config.custom.impermanence.enable
    "${config.custom.impermanence.base}/services/<service>";

  # Use mkOverride 999 if the option has a low-priority default
  services.<service>.dataDir = lib.mkIf config.custom.impermanence.enable
    (lib.mkOverride 999 "${config.custom.impermanence.base}/services/<service>");
};
```

**Path conventions:**
- Most services: `${config.custom.impermanence.base}/services/<service>`
- System-level services (systemd units in `/var/lib`): `${config.custom.impermanence.base}/system/var/lib/<service>`

**Configuration options typically used:** `dataDir`, `stateDir`, `dataPath`, or service-specific options

**Pattern 2: Persist via extraDirs**

When the service does not support configuring its data directory, add the default path to `extraDirs`:

```nix
# In the service's module
config = lib.mkIf cfg.enable {
  custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable
    [ "/var/lib/<service>" ];
};
```

Both patterns are in active use across the codebase. Check existing service modules for precedent when adding a new service.

**DynamicUser Services**

Services using `DynamicUser = true` store data in `/var/lib/private/<service>`. These require both persistence and a service dependency:

```nix
config = lib.mkIf cfg.enable {
  custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable
    [ "/var/lib/private/<service>" ];

  systemd.services.<service> = {
    after = [ "network-online.target" ]
      ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];
    wants = [ "network-online.target" ]
      ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];
  };
};
```

Note: DynamicUser services using `CacheDirectory` instead of `StateDirectory` store data in `/var/cache` and typically do not need persistence or the fix service.

**Cross-Cutting Services**

Add truly cross-cutting services (those that may be enabled from any module, e.g., PostgreSQL, Bluetooth) directly to `modules/impermanence.nix`. Most services should handle their own persistence within their module.

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