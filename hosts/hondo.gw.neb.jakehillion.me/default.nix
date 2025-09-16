{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-glinet-axt1800/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
  };
}
