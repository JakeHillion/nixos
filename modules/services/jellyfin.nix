{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.jellyfin;
in
{
  options.custom.services.jellyfin = {
    enable = lib.mkEnableOption "jellyfin";
  };

  config = lib.mkIf cfg.enable {
    users.users.jellyfin.uid = config.ids.uids.jellyfin;
    users.groups.jellyfin.gid = config.ids.gids.jellyfin;

    services.jellyfin = {
      enable = true;

      cacheDir = "${config.services.jellyfin.dataDir}/cache";
    };
  };
}
