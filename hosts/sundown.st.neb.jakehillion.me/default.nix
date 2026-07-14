{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-qnap-ts-1079-pro
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;

    ogygia.nebula = {
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        djz8PYS2HChYEMxJ6jCmSMEVJETh0Uofwtyr9qeNc1k=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Custom Services
    custom.tang.enable = true;
    custom.auto_updater.allowReboot = true;
  };
}
