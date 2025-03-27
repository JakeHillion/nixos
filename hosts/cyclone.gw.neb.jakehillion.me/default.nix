{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-topton-1u-10g/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.tang.enable = true;
  };
}
