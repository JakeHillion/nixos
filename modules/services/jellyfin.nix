{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.jellyfin;
in
{
  options.custom.services.jellyfin = {
    enable = lib.mkEnableOption "jellyfin";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin.dataDir = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "${config.custom.impermanence.base}/services/jellyfin");

    users.users.jellyfin.uid = config.ids.uids.jellyfin;
    users.groups.jellyfin.gid = config.ids.gids.jellyfin;

    services.jellyfin = {
      enable = true;

      cacheDir = "${config.services.jellyfin.dataDir}/cache";
    };
  };
}
