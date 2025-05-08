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
    wanMacAddress = "00:11:22:33:44:55"; # Optional, for ISP identification
    staticWanIP = "203.0.113.5"; # WAN IP for NAT loopback (even if DHCP is used)

    networks = {
      lan = {
        description = "Main LAN Network";
        subnet = "10.0.0.0/24";
        interface = "eth1";
        dhcpEnabled = true;
        dhcpPool = {
          start = "10.0.0.64";
          end = "10.0.0.254";
        };
        reservedIps = {
          "20" = {
            hostname = "desktop";
            fqdn = "desktop.example.com"; # FQDN for the device
            hwAddress = "00:11:22:33:44:66";
            dhcpReservation = true;
          };
          "25" = {
            hostname = "static-server";
            fqdn = "static-server.example.com";
            hwAddress = null; # Optional for static IP records
            dhcpReservation = false; # Not a DHCP reservation, just for documentation
          };
        };
        dnsServers = [ "1.1.1.1" "8.8.8.8" ];
        internetAccess = true;
        trustedNetwork = true;
      };
      
      iot = {
        description = "IoT Devices Network";
        vlanId = 10; # Creates VLAN interface
        subnet = "10.0.10.0/24";
        interface = "eth1"; # Parent interface for VLAN
        internetAccess = true;
        trustedNetwork = false;
      };
      
      cameras = {
        description = "Security Cameras";
        vlanId = 20;
        subnet = "10.0.20.0/24";
        interface = "eth1";
        portForwarding = []; # Each network can have its own port forwarding rules
        internetAccess = false; # No internet for cameras
        trustedNetwork = false;
      };
      
      # Each network can have its own port forwarding rules
      lan = {
        # ... other lan configuration ...
        
        # Port forwarding rules for LAN network
        portForwarding = [
          # Port forwarding by IP
          {
            description = "Web Server";
            externalPort = 80;
            internalIP = "10.0.0.20"; # Explicitly specify IP
            internalPort = 8080; # Optional, defaults to externalPort if not specified
            protocol = "tcp"; # can be "tcp", "udp", or "both"
            loopbackEnabled = false; # Disable NAT loopback (default: true)
          },
          
          # Port forwarding by FQDN (IP will be looked up from reservedIps)
          {
            description = "Database";
            externalPort = 5432; 
            fqdn = "desktop.example.com"; # Will resolve to 10.0.0.20
            protocol = "tcp";
          },
          
          # Router service (using gateway IP)
          {
            description = "SSH";
            externalPort = 22;
            internalIP = "10.0.0.1"; # Gateway IP = router itself 
            protocol = "tcp";
            loopbackEnabled = true; # Enable NAT loopback (optional, true by default)
          }
        ];
  };
};

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

### FQDN-based Port Forwarding

The router module supports port forwarding using FQDNs:

1. FQDNs defined in `reservedIps` can be referenced in port forwarding rules
2. The IP is automatically resolved based on the FQDN when generating nftables rules
3. This allows referring to devices by name rather than IP in the configuration

Example usage in port forwarding:
```nix
portForwarding = [
  {
    description = "Web Application";
    externalPort = 8080;
    fqdn = "app-server.lan.example.com"; # Will be resolved automatically
    internalPort = 8000;
    protocol = "tcp";
  }
];
```

Note: DNS resolution must be configured separately for proper name resolution within the network.

## Coding Conventions

- **Avoid global `with lib;`**: Never use global `with lib;` statements in modules. Instead, use fully qualified names (e.g., `lib.mkOption`, `lib.strings.concatStringsSep`, etc.). This improves code readability and avoids namespace conflicts.

## Common Errors and Solutions

- **FQDN comparison issues**: When comparing hostnames, use the full FQDN
- **VLAN interface errors**: Make sure parent interfaces are correctly defined

## Development Workflow

1. Make changes to configuration
2. Format code with `nix fmt`
3. Test with `nix build` for specific host
4. Commit changes
5. Apply on target system with `nixos-rebuild switch`

IMPORTANT: Always run `nix fmt` before committing changes to ensure consistent code formatting.

## File Management and Nix Evaluation

IMPORTANT: When adding new files to the repository, you must run `git add <file>` before Nix commands will recognize them. Nix evaluates the repository based on what Git knows about, not just what's on the filesystem. Files don't need to be committed, but they do need to be added to the Git index for Nix to see them.