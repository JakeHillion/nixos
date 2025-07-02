{ config, pkgs, lib, ... }:

let
  cfg = config.custom.backups.radicale;
in
{
  options.custom.backups.radicale = {
    enable = lib.mkEnableOption "radicale backup";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."backups/radicale/restic/128G" = {
      file = ../../secrets/restic/128G.age;
      owner = "radicale";
      group = "radicale";
    };

    services.restic.backups."radicale" = {
      user = "radicale";
      timerConfig = {
        OnBootSec = "15m";
        OnUnitInactiveSec = "30m";
        RandomizedDelaySec = "5m";
      };
      repository = "rest:https://restic.neb.jakehillion.me/128G";
      passwordFile = config.age.secrets."backups/radicale/restic/128G".path;
      paths = [
        config.services.radicale.settings.storage.filesystem_folder
      ];
    };
  };
}
