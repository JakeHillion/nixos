{ config, lib, ... }:

# Configures a host's network interface from its record in the network
# registry: the same record its switch port is configured from.

let
  cfg = config.custom.networking.host;
  inherit (config.custom.network) networks self;

  ip = import ./lib.nix { inherit lib; };

  static = lib.attrsets.filterAttrs (_: membership: membership.address == "static") self.net;
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
      interfaces.${cfg.interface} = {
        ipv4.addresses = lib.attrsets.mapAttrsToList
          (netName: membership: {
            address = membership.ipv4;
            prefixLength = ip.prefixLength networks.${netName}.ipv4;
          })
          static;

        mtu = self.mtu;
      };

      # networkd needs the gateway's interface named. Scripted networking finds
      # it from the address, and given a name adds a host route to the gateway.
      defaultGateway = lib.mkIf (static != { }) ({
        address = networks.${lib.lists.head (lib.attrsets.attrNames static)}.gateway;
      } // lib.attrsets.optionalAttrs config.networking.useNetworkd {
        interface = cfg.interface;
      });
    };
  };
}
