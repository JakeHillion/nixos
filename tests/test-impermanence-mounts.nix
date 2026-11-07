# Impermanence with cache enabled snapshot test
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
      custom.impermanence.cache = {
        enable = true;
        device = "/dev/sda3";
      };
    }];
  };

in
{
  fileSystems."/data".neededForBoot = config.config.fileSystems."/data".neededForBoot;
  environment.persistence = builtins.attrNames config.config.environment.persistence;
}
