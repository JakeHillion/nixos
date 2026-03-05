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
                addresses = [ "tcp://${name}.${config.ogygia.domain}:22000" ];
              })
              {
                "be.lt" = "QKNSUEX-XGJIDH3-5DM5MFY-7ES5AVO-ERJ447V-RKS553C-3PGMIJI-Y4YRZAF";
                "bob.lt" = "J5BTK7J-4UV6EBD-K45UNV4-UGZ57YN-2PWNBPW-IO2IJ24-VB23JFV-EBCH6A7";
                "boron.cx" = "LX5YKSC-SV22B4A-ESU7YPL-AANIT55-OVT3UJN-3FKNKUF-E7AOTOW-MMPNJQL";
                "jakehillion-mba-m2-15.lt" = "7NAXX6J-4RRJD6B-NP5LG3L-LUIGASI-OXLPS3H-ACLCXBA-RZNSRXN-CXMFZQC";
                "jakes-ipad.mob" = "QPNNJBC-SZQG4ZH-J7R4M2B-YUY6DLH-DFP6HBS-ASPKR5S-CARCET3-OBJAGAI";
                "jakes-iphone.mob" = "QHG6BBS-UPCFLPE-2OZGDZR-QUSKLVP-NEEEGXG-E6TMAXU-7YUHJ4I-AWLDKAB";
                "maverick.cx" = "7T6JSBR-WM6TQEX-T46WRPS-6YKYGA3-OHOXOCQ-ULBYH7K-W7ZGZFC-NJTXBQO";
                "merlin.rig" = "IUCUUDQ-7Q3VCA3-JMUA3GL-UOYWAPM-IE6RT3O-CTSA5VL-HRXEPZD-SSOBKQ2";
                "phoenix.st" = "65COGEC-WBF67I4-EBM73U3-DQMVOS7-PWM7VMS-M744STW-TQVIO7S-NBP56AV";
                "rooster.cx" = "YT53NDL-CEBZTYN-SVPSFOQ-GR5JNF6-JWWCZFE-UOKT4HL-QKRCKZ3-T7IZOAE";
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
                allComputers = lib.lists.filter (x: !builtins.elem x [ "jakes-ipad.mob" "jakes-iphone.mob" ]) allDevices;
              in
              with lib.attrsets; mapAttrs'
                (name: value: (nameValuePair "${cfg.baseDir}/${name}" (value // {
                  enable = lib.lists.any (x: x == (lib.concatStringsSep "." (lib.take 2 (lib.splitString "." config.networking.fqdn)))) value.devices;

                  label = name;
                })))
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
                    devices = [ "bob.lt" "phoenix.st" ];
                  };
                  "media/travel-shows" = {
                    id = "amylaceous-directionless-methyl";
                    devices = [ "bob.lt" "phoenix.st" ];
                  };

                  "appdata/zotero" = {
                    id = "sustainable-horizontal-skating";
                    devices = [
                      "jakehillion-mba-m2-15.lt"
                      "jakes-ipad.mob"
                      "merlin.rig"
                      "phoenix.st"
                    ];
                  };

                  "appdata/supobot" = {
                    id = "contaminated-ample-demonisation";
                    devices = allDevices;
                  };

                  "appdata/claude" = {
                    id = "periodical-disjoint-pier";
                    devices = [
                      "bob.lt"
                      "maverick.cx"
                      "merlin.rig"
                      "rooster.cx"
                    ];
                  };

                  "appdata/blackmagic-cam" = {
                    id = "thermodynamic-ultramodern-asynchronism";
                    devices = [ "jakes-iphone.mob" "phoenix.st" ];
                    # Sync smallest files first so the importer can
                    # process and free remote storage more quickly.
                    order = "smallestFirst";
                  };

                  "media/offline-youtube" = {
                    id = "receding-accidental-leprosy";
                    devices = [ "bob.lt" "phoenix.st" ];
                  };
                };
          };
      };
    }

    (lib.mkIf cfg.backups.enable {
      age.secrets = {
        "restic/syncthing/mig29.key" = {
          file = ../secrets/restic/mig29.age;
          owner = "jake";
          group = "users";
        };
        "restic/syncthing/b52.key" = {
          file = ../secrets/restic/b52.age;
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
          fullExcludes = [
            "${cfg.baseDir}/.st"
            "${cfg.baseDir}/*/.stfolder"
            "${cfg.baseDir}/appdata/blackmagic-cam"
            "${cfg.baseDir}/media/travel-shows"
            "${cfg.baseDir}/media/offline-youtube"
          ];
        in
        {
          "syncthing-mig29" = {
            repository = "rest:https://restic.${config.ogygia.domain}/mig29";
            user = "jake";
            passwordFile = config.age.secrets."restic/syncthing/mig29.key".path;

            timerConfig = {
              OnBootSec = "10m";
              OnUnitInactiveSec = "15m";
              RandomizedDelaySec = "5m";
            };

            paths = [ cfg.baseDir ];
            exclude = rareBackups ++ fullExcludes;
          };
          "syncthing-b52" = {
            repository = "rest:https://restic.${config.ogygia.domain}/b52";
            user = "jake";
            passwordFile = config.age.secrets."restic/syncthing/b52.key".path;

            timerConfig = {
              OnBootSec = "30m";
              OnUnitInactiveSec = "24h";
              RandomizedDelaySec = "1h";
            };

            paths = [ cfg.baseDir ];
            exclude = fullExcludes;
          };
        };
    })
  ]);
}
