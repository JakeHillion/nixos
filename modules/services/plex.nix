{ config, lib, ... }:

let
  cfg = config.custom.services.plex;
in
{
  options.custom.services.plex = {
    enable = lib.mkEnableOption "plex";
  };

  config = lib.mkIf cfg.enable {
    custom.filesystems = {
      tv.enable = true;
      films.enable = true;
    };
  };
}
