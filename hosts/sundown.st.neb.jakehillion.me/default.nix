{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-qnap-ts-1079-pro/default.nix
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;

    ## Custom Services
    custom.tang.enable = true;
    custom.auto_updater.allowReboot = true;
  };
}
