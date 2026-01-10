# Basic impermanence module snapshot test
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
    }];
  };

  # Extract just the essential mount info
  simplifyMount = m: { what = m.what; where = m.where; };

in
{
  fileSystems."/data".neededForBoot = config.config.fileSystems."/data".neededForBoot;
  systemd.mounts = map simplifyMount config.config.systemd.mounts;
  systemd.tmpfiles.rules = config.config.systemd.tmpfiles.rules;
}
