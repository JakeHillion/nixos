{ pkgs, lib, config, nixpkgs-unstable, ... }:

let
  cfg = config.custom.resilio;
in
{
  imports = [ "${nixpkgs-unstable}/nixos/modules/services/networking/resilio.nix" ];
  disabledModules = [ "services/networking/resilio.nix" ];

  options.custom.resilio = {
    enable = lib.mkEnableOption "resilio";

    extraUsers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ config.custom.user ];
    };

    folders = lib.mkOption {
      type = with lib.types; uniq (listOf attrs);
      default = [ ];
    };

    backups = {
      enable = lib.mkEnableOption "resilio.backups";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      users.users =
        let
          mkUser =
            (user: {
              name = user;
              value = {
                extraGroups = [ "rslsync" ];
              };
            });
        in
        builtins.listToAttrs (builtins.map mkUser cfg.extraUsers);

      age.secrets =
        let
          mkSecret = (secret: {
            name = secret.name;
            value = {
              file = secret.file;
              owner = "rslsync";
              group = "rslsync";
            };
          });
        in
        builtins.listToAttrs (builtins.map (folder: mkSecret folder.secret) cfg.folders);

      services.resilio = {
        enable = true;
        deviceName = lib.mkOverride 999 (lib.strings.concatStringsSep "." (lib.lists.take 2 (lib.strings.splitString "." config.networking.fqdnOrHostName)));

        storagePath = lib.mkOverride 999 "${config.services.resilio.directoryRoot}/.sync";

        sharedFolders =
          let
            mkFolder = name: secret: {
              directory = "${config.services.resilio.directoryRoot}/${name}";
              secretFile = "${config.age.secrets."${secret.name}".path}";
              knownHosts = [ ];
              searchLAN = true;
              useDHT = true;
              useRelayServer = true;
              useSyncTrash = false;
              useTracker = true;
            };
          in
          builtins.map (folder: mkFolder folder.name folder.secret) cfg.folders;
      };

      systemd.services.resilio.unitConfig.RequiresMountsFor = builtins.map (folder: "${config.services.resilio.directoryRoot}/${folder.name}") cfg.folders;
    }

    (lib.mkIf cfg.backups.enable {
      age.secrets."resilio/restic/128G.key" = {
        file = ../secrets/restic/128G.age;
        owner = "rslsync";
        group = "rslsync";
      };
      age.secrets."resilio/restic/1.6T.key" = {
        file = ../secrets/restic/1.6T.age;
        owner = "rslsync";
        group = "rslsync";
      };

      services.restic.backups."resilio-128G" = {
        repository = "rest:https://restic.ts.hillion.co.uk/128G";
        user = "rslsync";
        passwordFile = config.age.secrets."resilio/restic/128G.key".path;

        timerConfig = {
          OnBootSec = "10m";
          OnUnitInactiveSec = "15m";
          RandomizedDelaySec = "5m";
        };

        paths = [ config.services.resilio.directoryRoot ];
        exclude = [
          "${config.services.resilio.directoryRoot}/.sync"
          "${config.services.resilio.directoryRoot}/*/.sync"

          "${config.services.resilio.directoryRoot}/dad/media"
          "${config.services.resilio.directoryRoot}/resources/media"
        ];
      };
      services.restic.backups."resilio-1.6T" = {
        repository = "rest:https://restic.ts.hillion.co.uk/1.6T";
        user = "rslsync";
        passwordFile = config.age.secrets."resilio/restic/1.6T.key".path;

        timerConfig = {
          OnBootSec = "30m";
          OnUnitInactiveSec = "24h";
          RandomizedDelaySec = "1h";
        };

        paths = [
          "${config.services.resilio.directoryRoot}/resources/media/audiobooks"
          "${config.services.resilio.directoryRoot}/resources/media/home"
          "${config.services.resilio.directoryRoot}/resources/media/iso"
        ];
      };
    })
  ]);
}
