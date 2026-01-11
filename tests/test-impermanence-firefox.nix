# Test Firefox persistence - verifies bindfs mount in activation script
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
      custom.desktop.firefox.enable = true;
    }];
  };

in
{
  home-manager.users.jake.home.activation.createAndMountPersistentStoragePaths.data =
    config.config.home-manager.users.jake.home.activation.createAndMountPersistentStoragePaths.data;
}
