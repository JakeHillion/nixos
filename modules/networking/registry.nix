{ config, lib, ... }:

# The fleet's network registry: the facts about the home networks that more
# than one machine has to agree on. The data lives in /network; this module
# only gives it a schema.

let
  ip = import ./lib.nix { inherit lib; };

  cfg = config.custom.network;

  checkDevice = name: device: device // {
    net = lib.attrsets.mapAttrs
      (netName: membership:
        let
          network = cfg.networks.${netName} or (throw "network/devices.toml: ${name} is on ${netName}, which is not in network/networks.toml");
          prefixes = [ network.ipv4 ] ++ lib.lists.optional (network.routed4 != null) network.routed4;
        in
        if lib.lists.any (prefix: ip.contains prefix membership.ipv4) prefixes then membership
        else throw "network/devices.toml: ${name} has ${membership.ipv4} on ${netName}, which is outside ${lib.strings.concatStringsSep " and " prefixes}")
      device.net;
  };
in
{
  options.custom.network = {
    networks = lib.mkOption {
      readOnly = true;
      description = "Network segments, by name.";
      type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
        options = {
          vlan = lib.mkOption {
            type = lib.types.ints.between 1 4094;
            description = "VLAN ID of the network.";
          };

          ipv4 = lib.mkOption {
            type = lib.types.str;
            description = "IPv4 prefix of the network, in CIDR notation.";
          };

          routed4 = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Public IPv4 prefix the ISP routes to the router, whose addresses are on-link on the network.";
          };

          router = lib.mkOption {
            type = lib.types.str;
            description = "Device that routes the network.";
          };

          gateway = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = ip.host config.ipv4 1;
            description = "IPv4 address of the router on the network: the first address of its prefix.";
          };

          pool = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule {
              options = {
                start = lib.mkOption {
                  type = lib.types.str;
                  description = "First address of the pool.";
                };
                end = lib.mkOption {
                  type = lib.types.str;
                  description = "Last address of the pool.";
                };
              };
            });
            default = null;
            description = "Addresses the router hands out over DHCP. Without a pool the network has no DHCP.";
          };
        };
      }));
    };

    devices = lib.mkOption {
      readOnly = true;
      description = ''
        Network interfaces of the devices on the networks, by device name.
        Fleet hosts are named by their FQDN without the fleet domain.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          mac = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "MAC address of the interface. Without one the device gets no DHCP reservation.";
          };

          net = lib.mkOption {
            description = "Networks the interface is on, by network name.";
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                ipv4 = lib.mkOption {
                  type = lib.types.str;
                  description = "IPv4 address of the interface on the network.";
                };
              };
            });
          };
        };
      });
      apply = lib.attrsets.mapAttrs checkDevice;
    };
  };

  config.custom.network = {
    networks = lib.trivial.importTOML ../../network/networks.toml;
    devices = lib.trivial.importTOML ../../network/devices.toml;
  };
}
