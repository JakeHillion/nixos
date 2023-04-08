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
  };
}
