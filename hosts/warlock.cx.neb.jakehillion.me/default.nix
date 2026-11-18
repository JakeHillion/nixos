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
      nameservers = lib.mkBefore [ config.custom.network.networks.lan.gateway ];
    };
    custom.networking.host = {
      enable = true;
      interface = "enp2s0";
    };

    services.resolved.enable = false;
  };
}
