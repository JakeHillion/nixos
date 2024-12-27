{ config, pkgs, lib, ... }:

let
  cfg = config.custom.backups.matrix;
in
{
  options.custom.backups.matrix = {
    enable = lib.mkEnableOption "matrix";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."backups/matrix/restic/128G".file = ../../secrets/restic/128G.age;

    services = {
      postgresqlBackup = {
        enable = true;
        compression = "none"; # for better diffing
        databases = [ "matrix-synapse" ];
      };

      restic.backups."matrix" = {
        user = "root";
        timerConfig = {
          OnCalendar = "03:00";
          RandomizedDelaySec = "60m";
        };
        repository = "rest:https://restic.neb.jakehillion.me/128G";
        passwordFile = config.age.secrets."backups/matrix/restic/128G".path;
        paths = [
          "${config.services.postgresqlBackup.location}/matrix-synapse.sql"
          config.services.matrix-synapse.dataDir
        ];
      };
    };
  };
}
