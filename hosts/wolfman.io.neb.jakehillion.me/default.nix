{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-smx11ssh-ln4f
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;

    # First boot: no signed Nebula cert exists yet. Bring the machine up
    # without Nebula, then generate + sign the cert and drop this line.
    ogygia.nebula.enable = lib.mkForce false;

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        PLACEHOLDER_REPLACE_AFTER_FIRST_BOOT=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Custom Services
    custom.tang.enable = true;

    ## Automatic updates
    ogygia.updated.settings.activate.allow_reboot = true;
  };
}
