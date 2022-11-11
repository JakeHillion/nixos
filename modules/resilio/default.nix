{ pkgs, lib, config, ... }:

{
  options.resilioFolders = lib.mkOption {
    type = with lib.types; uniq (listOf attrs);
    default = [];
  };

  config.services.resilio.sharedFolders =
    let
      mkFolder = name: secret: {
        directory = "${config.services.resilio.directoryRoot}/${name}";
        secret = "${secret}";
        knownHosts = [];
        searchLAN = true;
        useDHT = true;
        useRelayServer = true;
        useSyncTrash = false;
        useTracker = true;
      };
    in builtins.map (folder: mkFolder folder.name folder.secret) config.resilioFolders;
}

