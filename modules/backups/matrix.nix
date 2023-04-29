{ config, pkgs, lib, ... }:

let
  cfg = config.custom.backups.matrix;
in
{
  options.custom.backups.matrix = {
    enable = lib.mkEnableOption "matrix";
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "backblaze/vm-strangervm-backups-matrix" = {
        file = ../../secrets/backblaze/vm-strangervm-backups-matrix.age;
      };
      "restic/b2-backups-matrix" = {
        file = ../../secrets/restic/b2-backups-matrix.age;
      };
    };

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
          RandomizedDelaySec = "30m";
        };
        repository = "b2:hillion-personal:backups/matrix";
        pruneOpts = [
          "--keep-daily 14"
          "--keep-weekly 5"
          "--keep-monthly 24"
          "--keep-yearly 10"
        ];
        passwordFile = config.age.secrets."restic/b2-backups-matrix".path;
        environmentFile = config.age.secrets."backblaze/vm-strangervm-backups-matrix".path;
        paths = [
          "${config.services.postgresqlBackup.location}/matrix-synapse.sql"
          config.services.matrix-synapse.dataDir
        ];
      };
    };
  };
}
