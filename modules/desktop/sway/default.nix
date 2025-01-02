{ config, pkgs, lib, ... }:

let
  cfg = config.custom.desktop.sway;
in
{
  options.custom.desktop.sway = {
    enable = lib.mkEnableOption "sway";
  };

  config = lib.mkIf cfg.enable {
    programs.sway.enable = true;
  };
}
