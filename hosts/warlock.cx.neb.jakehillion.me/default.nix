{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-beelink-eq14
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        eIouUmARUnd+D3DWBFR1m76f7R6nSgDyTu+ID5YaDyQ=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Custom Services
    custom.tang.enable = true;

    ## Automatic updates
    ogygia.updated.settings.activate.allow_reboot = true;

    networking = {
      useNetworkd = true;
      vlans = {
        iot = {
          id = 2;
          interface = "enp2s0";
        };
      };
      interfaces.iot.useDHCP = true;
      nameservers = lib.mkBefore [ "10.64.50.1" ];
    };

    systemd.network.networks."40-iot".dhcpV4Config = {
      UseGateway = false;
      UseDNS = false;
    };

    # Only the LAN is needed to reach tang in initrd.
    boot.initrd.systemd.network = {
      netdevs."40-iot".enable = false;
      networks."40-iot".enable = false;
      networks."40-enp2s0".vlan = lib.mkForce [ ];
    };

    services.resolved.enable = false;
  };
}
