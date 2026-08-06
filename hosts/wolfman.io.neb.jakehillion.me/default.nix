{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-smx11ssh-ln4f
  ];

  config = {
    system.stateVersion = "26.05";

    custom.defaults = true;

    ogygia.nebula = {
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        2M4oWEsJoTZUYdrOIbavJhVBNt66omwQS9mG63fQgSo=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Custom Services
    custom.tang.enable = true;
  };
}
