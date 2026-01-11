# Test Claude persistence - verifies bindfs mounts in activation script
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
      custom.home.claude.enable = true;
    }];
  };

in
{
  home-manager.users.jake.home.activation.createAndMountPersistentStoragePaths.data =
    config.config.home-manager.users.jake.home.activation.createAndMountPersistentStoragePaths.data;
}
