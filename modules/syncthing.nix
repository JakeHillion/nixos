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

        settings =
          let
            devices = lib.attrsets.mapAttrs
              (name: value: {
                id = value;
                addresses = [ "tcp://${name}.neb.jakehillion.me:22000" ];
              })
              {
                "boron.cx" = "LX5YKSC-SV22B4A-ESU7YPL-AANIT55-OVT3UJN-3FKNKUF-E7AOTOW-MMPNJQL";
                "gendry.jakehillion-terminals" = "7JSM6OY-SYSZXM5-633SD6U-ZZJ5KN3-SZQNQFY-C7RGOLM-DZG3CUW-JCVR2AH";
                "jakehillion-mba-m2-15.lt" = "7NAXX6J-4RRJD6B-NP5LG3L-LUIGASI-OXLPS3H-ACLCXBA-RZNSRXN-CXMFZQC";
                "jakes-iphone.mob" = "QHG6BBS-UPCFLPE-2OZGDZR-QUSKLVP-NEEEGXG-E6TMAXU-7YUHJ4I-AWLDKAB";
                "merlin.rig" = "IUCUUDQ-7Q3VCA3-JMUA3GL-UOYWAPM-IE6RT3O-CTSA5VL-HRXEPZD-SSOBKQ2";
                "phoenix.st" = "65COGEC-WBF67I4-EBM73U3-DQMVOS7-PWM7VMS-M744STW-TQVIO7S-NBP56AV";
              };
          in
          {
            options = {
              globalAnnounceEnabled = false;
              localAnnounceEnabled = false;
              natEnabled = false;
              relaysEnabled = false;
              urAccepted = -1;

              listenAddresses = [ "tcp://${config.custom.dns.nebula.ipv4}:22000" ];
            };

            inherit devices;

            folders =
              let
                allDevices = builtins.attrNames devices;
                allComputers = lib.lists.remove "jakes-iphone.mob" allDevices;
              in
              with lib.attrsets; mapAttrs'
                (name: value: (nameValuePair "${cfg.baseDir}/${name}" {
                  enable = lib.lists.any (x: x == (lib.concatStringsSep "." (lib.take 2 (lib.splitString "." config.networking.fqdn)))) value.devices;

                  id = value.id;
                  label = name;
                  devices = value.devices;
                }))
                {
                  "sync" = {
                    id = "unaggressive-aggravating-reagent";
                    devices = allDevices;
                  };
                  "projects" = {
                    id = "tired-reflected-waterfall";
                    devices = allComputers;
                  };

                  "media/audiobooks" = {
                    id = "spherical-tagged-muenster";
                    devices = [ "jakehillion-mba-m2-15.lt" "phoenix.st" ];
                  };

                  "appdata/zotero" = {
                    id = "sustainable-horizontal-skating";
                    devices = [
                      "jakehillion-mba-m2-15.lt"
                      "merlin.rig"
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
          owner = "jake";
          group = "users";
        };
        "restic/syncthing/1.6T.key" = {
          file = ../secrets/restic/1.6T.age;
          owner = "jake";
          group = "users";
        };
      };

      services.restic.backups =
        let
          rareBackups = [
            "${cfg.baseDir}/archive"
            "${cfg.baseDir}/media/audiobooks"
          ];
        in
        {
          "syncthing-128G" = {
            repository = "rest:https://restic.neb.jakehillion.me/128G";
            user = "jake";
            passwordFile = config.age.secrets."restic/syncthing/128G.key".path;

            timerConfig = {
              OnBootSec = "10m";
              OnUnitInactiveSec = "15m";
              RandomizedDelaySec = "5m";
            };

            paths = [ cfg.baseDir ];
            exclude = [
              "${cfg.baseDir}/.st"
              "${cfg.baseDir}/*/.stfolder"
            ] ++ rareBackups;
          };
          "syncthing-1.6T" = {
            repository = "rest:https://restic.neb.jakehillion.me/1.6T";
            user = "jake";
            passwordFile = config.age.secrets."restic/syncthing/1.6T.key".path;

            timerConfig = {
              OnBootSec = "30m";
              OnUnitInactiveSec = "24h";
              RandomizedDelaySec = "1h";
            };

            paths = [ cfg.baseDir ];
          };
        };
    })
  ]);
}
