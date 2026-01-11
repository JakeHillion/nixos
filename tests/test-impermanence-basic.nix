# Basic impermanence module snapshot test
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
    }];
  };

in
{
  fileSystems."/data".neededForBoot = config.config.fileSystems."/data".neededForBoot;
  environment.persistence = builtins.attrNames config.config.environment.persistence;
}
