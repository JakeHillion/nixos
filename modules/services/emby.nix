{ config, lib, ... }:

let
  cfg = config.custom.services.emby;
in
{
  options.custom.services.emby = {
    enable = lib.mkEnableOption "emby";
  };

  config = lib.mkIf cfg.enable {
    custom.filesystems = {
      tv.enable = true;
      films.enable = true;
    };
  };
}
