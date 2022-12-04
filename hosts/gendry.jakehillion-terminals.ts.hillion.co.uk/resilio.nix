{ config, pkgs, lib, ... }:

let
  folderNames = [
    "dad"
    "joseph"
    "projects"
    "resources"
    "sync"
  ];
in
{
  imports = [
    ../../modules/resilio/default.nix
  ];

  ## Resilio Sync (Unencrypted)
  config.services.resilio.enable = true;
  config.services.resilio.deviceName = "gendry.jakehillion-terminals";
  config.services.resilio.directoryRoot = "/data/sync";
  config.services.resilio.storagePath = "/data/sync/.sync";

  config.age.secrets =
    let
      mkSecret = name: {
        name = "resilio/plain/${name}";
        value = {
          file = ../../secrets/resilio/plain/${name}.age;
          owner = "rslsync";
          group = "rslsync";
        };
      };
    in
    builtins.listToAttrs (builtins.map (mkSecret) folderNames);

  config.resilioFolders =
    let
      mkFolder = name: {
        name = name;
        secretFile = config.age.secrets."resilio/plain/${name}".path;
      };
    in
    builtins.map (mkFolder) folderNames;
}
