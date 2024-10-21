{ pkgs, lib, config, ... }:

let
  cfg = config.custom.resilio;
in
{
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
  };

  config = lib.mkIf cfg.enable {
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
  };
}
