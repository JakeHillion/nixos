{ config, lib, ... }:

let
  cfg = config.custom.filesystems;
in
{
  options.custom.filesystems = {
    films = {
      enable = lib.mkEnableOption "mounting films";
      host = lib.mkOption {
        default = "archnas.storage.ts.hillion.co.uk";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/media/films";
        description = "Path at which to mount";
      };
      localPath = lib.mkOption {
        default = "/data/media/films";
      };
      remotePath = lib.mkOption {
        default = {
          type = "cifs";
          share = "films";
          credentials = config.age.secrets."filesystems/films".path;
        };
      };
    };

    tv = {
      enable = lib.mkEnableOption "mounting tv";
      host = lib.mkOption {
        default = "archnas.storage.ts.hillion.co.uk";
      };
      localPath = lib.mkOption {
        default = "/data/media/tv";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/media/tv";
        description = "Path at which to mount";
      };
      remotePath = lib.mkOption {
        default = {
          type = "cifs";
          share = "tv";
          credentials = config.age.secrets."filesystems/tv".path;
        };
      };
    };
  };

  config = {
    age.secrets = {
      "filesystems/films" = lib.mkIf cfg.tv.enable { file = ../secrets/filesystems/films.age; };
      "filesystems/tv" = lib.mkIf cfg.tv.enable { file = ../secrets/filesystems/tv.age; };
    };
    fileSystems = {
      "${cfg.films.path}" = lib.mkIf cfg.films.enable (if cfg.films.host == config.networking.fqdn then {
        device = cfg.films.localPath;
        options = [ "bind" ];
      } else {
        device = "//${cfg.films.host}/${cfg.films.remotePath.share}";
        fsType = "cifs";
        options = [
          "x-systemd.automount"
          "noauto"
          "x-systemd.idle-timeout=60"
          "x-systemd.device-timeout=5s"
          "x-systemd.mount-timeout=5s"
          "credentials=${cfg.films.remotePath.credentials}"
        ];
      });
      "${cfg.tv.path}" = lib.mkIf cfg.tv.enable (if cfg.tv.host == config.networking.fqdn then {
        device = cfg.tv.localPath;
        options = [ "bind" ];
      } else {
        device = "//${cfg.tv.host}/${cfg.tv.remotePath.share}";
        fsType = "cifs";
        options = [
          "x-systemd.automount"
          "noauto"
          "x-systemd.idle-timeout=60"
          "x-systemd.device-timeout=5s"
          "x-systemd.mount-timeout=5s"
          "credentials=${cfg.tv.remotePath.credentials}"
        ];
      });
    };
  };
}
