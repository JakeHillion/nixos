{ pkgs, lib, config, ... }:

let
  cfg = config.custom.syncthing;
in
{
  options.custom.syncthing = {
    enable = lib.mkEnableOption "syncthing";

    baseDir = lib.mkOption {
      type = lib.types.str;
    };

    backups = {
      enable = lib.mkEnableOption "syncthing.backups";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.syncthing = {
        enable = true;

        user = "jake";

        configDir = lib.mkOverride 999 "${config.custom.syncthing.baseDir}/.st";

        settings = {
          options = {
            globalAnnounceEnabled = false;
            localAnnounceEnabled = false;
            natEnabled = false;
            relaysEnabled = false;
            urAccepted = -1;

            listenAddresses = [ "tcp://${config.custom.dns.nebula.ipv4}:22000" ];
          };

          devices = {
            "boron.cx" = {
              id = "LX5YKSC-SV22B4A-ESU7YPL-AANIT55-OVT3UJN-3FKNKUF-E7AOTOW-MMPNJQL";
              addresses = [ "tcp://172.20.0.1:22000" ];
            };
            "jakehillion-mba-m2-15.lt" = {
              id = "7NAXX6J-4RRJD6B-NP5LG3L-LUIGASI-OXLPS3H-ACLCXBA-RZNSRXN-CXMFZQC";
              addresses = [ "tcp://172.20.0.6:22000" ];
            };
            "phoenix.st" = {
              id = "65COGEC-WBF67I4-EBM73U3-DQMVOS7-PWM7VMS-M744STW-TQVIO7S-NBP56AV";
              addresses = [ "tcp://172.20.0.11:22000" ];
            };
          };

          folders = {
            "${cfg.baseDir}/sync" = {
              id = "unaggressive-aggravating-reagent";
              label = "sync";
              devices = [
                "boron.cx"
                "jakehillion-mba-m2-15.lt"
                "phoenix.st"
              ];
            };
          };
        };
      };
    }

    (lib.mkIf cfg.backups.enable {
      age.secrets = {
        "restic/syncthing/128G.key" = {
          file = ../secrets/restic/128G.age;
          owner = "syncthing";
          group = "syncthing";
        };
        "restic/syncthing/1.6T.key" = {
          file = ../secrets/restic/1.6T.age;
          owner = "syncthing";
          group = "syncthing";
        };
      };

      services.restic.backups = {
        "syncthing-128G" = {
          repository = "rest:https://restic.neb.jakehillion.me/128G";
          user = "jake";
          passwordFile = config.age.secrets."restic/syncthing/128G.key".path;

          timerConfig = {
            OnBootSec = "10m";
            OnUnitInactiveSec = "15m";
            RandomizedDelaySec = "5m";
          };
        };
        "syncthing-1.6T" = {
          repository = "rest:https://restic.neb.jakehillion.me/128G";
          user = "jake";
          passwordFile = config.age.secrets."restic/syncthing/1.6T.key".path;

          timerConfig = {
            OnBootSec = "30m";
            OnUnitInactiveSec = "24h";
            RandomizedDelaySec = "1h";
          };
        };
      };
    })
  ]);
}
