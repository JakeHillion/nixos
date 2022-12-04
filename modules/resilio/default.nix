{ pkgs, lib, config, nixpkgs-unstable, ... }:

{
  imports = [ "${nixpkgs-unstable}/nixos/modules/services/networking/resilio.nix" ];
  disabledModules = [ "services/networking/resilio.nix" ];

  options.resilioFolders = lib.mkOption {
    type = with lib.types; uniq (listOf attrs);
    default = [ ];
  };

  config.users.users.jake.extraGroups = [ "rslsync" ];

  config.services.resilio.sharedFolders =
    let
      mkFolder = name: secretFile: {
        directory = "${config.services.resilio.directoryRoot}/${name}";
        secretFile = "${secretFile}";
        knownHosts = [ ];
        searchLAN = true;
        useDHT = true;
        useRelayServer = true;
        useSyncTrash = false;
        useTracker = true;
      };
    in
    builtins.map (folder: mkFolder folder.name folder.secretFile) config.resilioFolders;
}
