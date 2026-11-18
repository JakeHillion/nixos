{ config, lib, ... }:

# Configures a host's network interface from its record in the network
# registry: the same record its switch port is configured from.

let
  cfg = config.custom.networking.host;
  inherit (config.custom.network) networks self;

  ip = import ./lib.nix { inherit lib; };

  # The untagged network is on the interface itself. A tagged network is a
  # VLAN interface named after the network.
  tagged = lib.attrsets.filterAttrs (_: membership: membership.tagged) self.net;
  interfaceOf = netName: if self.net.${netName}.tagged then netName else cfg.interface;

  addressed = address: lib.attrsets.filterAttrs (_: membership: membership.address == address) self.net;
  untaggedStatic = lib.attrsets.filterAttrs (_: membership: !membership.tagged) (addressed "static");

  perInterface = memberships: value:
    lib.attrsets.mapAttrs' (netName: _: lib.attrsets.nameValuePair (interfaceOf netName) value) memberships;
  perUnit = memberships: value:
    lib.attrsets.mapAttrs' (netName: _: lib.attrsets.nameValuePair "40-${netName}" (value netName)) memberships;
in
{
  options.custom.networking.host = {
    enable = lib.mkEnableOption "configuring the host's network interface from the network registry";

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Name of the interface the host's record in the registry describes.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      vlans = lib.attrsets.mapAttrs
        (netName: _: {
          id = networks.${netName}.vlan;
          interface = cfg.interface;
        })
        tagged;

      interfaces = lib.mkMerge [
        { ${cfg.interface}.mtu = self.mtu; }

        (lib.attrsets.mapAttrs'
          (netName: membership: lib.attrsets.nameValuePair (interfaceOf netName) {
            ipv4.addresses = [{
              address = membership.ipv4;
              prefixLength = ip.prefixLength networks.${netName}.ipv4;
            }];
          })
          (addressed "static"))

        (perInterface (addressed "dhcp") { useDHCP = true; })
      ];

      # networkd needs the gateway's interface named. Scripted networking finds
      # it from the address, and given a name adds a host route to the gateway.
      defaultGateway = lib.mkIf (untaggedStatic != { }) ({
        address = networks.${lib.lists.head (lib.attrsets.attrNames untaggedStatic)}.gateway;
      } // lib.attrsets.optionalAttrs config.networking.useNetworkd {
        interface = cfg.interface;
      });
    };

    systemd.network.networks = lib.mkIf config.networking.useNetworkd (lib.mkMerge [
      # Only the untagged network provides the default route and DNS
      (perUnit (lib.attrsets.filterAttrs (netName: _: tagged ? ${netName}) (addressed "dhcp")) (_: {
        dhcpV4Config = {
          UseGateway = false;
          UseDNS = false;
        };
      }))

      # A network carried without an address, for containers' macvlans
      (perUnit (addressed "none") (netName: {
        matchConfig.Name = netName;
        networkConfig.LinkLocalAddressing = "no";
        linkConfig.RequiredForOnline = "no";
      }))
    ]);

    # Only the untagged network is needed to reach tang in initrd
    boot.initrd.systemd.network = lib.mkIf (config.boot.initrd.network.enable && tagged != { }) {
      netdevs = perUnit tagged (_: { enable = false; });
      networks = perUnit tagged (_: { enable = false; }) // {
        "40-${cfg.interface}".vlan = lib.mkForce [ ];
      };
    };
  };
}
