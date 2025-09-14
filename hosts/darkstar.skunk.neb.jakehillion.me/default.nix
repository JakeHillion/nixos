{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-starfive-visionfive2/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.tang.enable = true;
  };
}
