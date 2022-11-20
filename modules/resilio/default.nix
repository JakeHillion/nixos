{ pkgs, lib, config, ... }:

{
  imports = [ ./nixpkgs-pr125803-modules_services_networking_resilio.nix ];
  disabledModules = [ "services/networking/resilio.nix" ];

  options.resilioFolders = lib.mkOption {
    type = with lib.types; uniq (listOf attrs);
    default = [ ];
  };

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
