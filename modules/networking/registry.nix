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
          prefixes = lib.lists.filter (prefix: prefix != null) [ network.ipv4 network.routed4 ];
        in
        if membership.ipv4 == null || lib.lists.any (prefix: ip.contains prefix membership.ipv4) prefixes then membership
        else throw "network/devices.toml: ${name} has ${membership.ipv4} on ${netName}, which is outside ${lib.strings.concatStringsSep " and " prefixes}")
      device.net;
  };

  # A key such as "31-36" stands for each port in the range. A port's own key
  # takes precedence over a range it falls in.
  expandPorts = ports:
    let
      isRange = key: lib.strings.hasInfix "-" key;
      expand = key:
        let
          bounds = map lib.strings.toInt (lib.strings.splitString "-" key);
        in
        map (port: lib.attrsets.nameValuePair (toString port) ports.${key})
          (lib.lists.range (lib.lists.head bounds) (lib.lists.last bounds));
    in
    lib.attrsets.listToAttrs (lib.lists.concatMap expand (lib.lists.filter isRange (lib.attrsets.attrNames ports)))
    // lib.attrsets.filterAttrs (key: _: !(isRange key)) ports;

  portFiles = lib.attrsets.filterAttrs (file: _: lib.strings.hasSuffix ".toml" file) (builtins.readDir ../../network/ports);
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
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "IPv4 prefix of the network, in CIDR notation.";
          };

          routed4 = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Public IPv4 prefix the ISP routes to the router, whose addresses are on-link on the network.";
          };

          router = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Device that routes the network.";
          };

          gateway = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            readOnly = true;
            default = if config.router != null then ip.host config.ipv4 1 else null;
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

          kind = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "edgeswitch" "unifi" ]);
            default = null;
            description = "For a managed switch, how it is configured. Its port table is the file named after it in network/ports.";
          };

          net = lib.mkOption {
            default = { };
            description = "Networks the interface is on, by network name.";
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                ipv4 = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "IPv4 address of the interface on the network.";
                };

                tagged = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Whether the interface carries the network as a tagged VLAN. An interface has at most one untagged network.";
                };
              };
            });
          };
        };
      });
      apply = lib.attrsets.mapAttrs checkDevice;
    };

    ports = lib.mkOption {
      readOnly = true;
      description = "Port tables of the managed switches: what each port is cabled to, by switch name and port number.";
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.coercedTo lib.types.str (device: { inherit device; }) (lib.types.submodule {
        options = {
          device = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Device cabled to the port. The port's VLANs are the networks of the device's interface.";
          };

          description = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Description of a port that is not cabled to a registered device.";
          };

          native = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Untagged network of a port that is not cabled to a registered device.";
          };

          tagged = lib.mkOption {
            type = lib.types.either (lib.types.enum [ "all" ]) (lib.types.listOf lib.types.str);
            default = [ ];
            description = "Tagged networks of a port that is not cabled to a registered device, or \"all\" for every other network.";
          };
        };
      })));
      apply = lib.attrsets.mapAttrs (_: expandPorts);
    };
  };

  config.custom.network = {
    networks = lib.trivial.importTOML ../../network/networks.toml;
    devices = lib.trivial.importTOML ../../network/devices.toml;
    ports = lib.attrsets.mapAttrs'
      (file: _: lib.attrsets.nameValuePair
        (lib.strings.removeSuffix ".toml" file)
        (lib.trivial.importTOML (../../network/ports + "/${file}")))
      portFiles;
  };
}
