# Test PostgreSQL persistence - verifies bind mount is created
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
      services.postgresql.enable = true;
    }];
  };

  pgDataDir = config.config.services.postgresql.dataDir;
  pgFs = config.config.fileSystems.${pgDataDir};

in
{
  # The actual system state: a bind mount from /data/system/... to the dataDir
  fileSystems.${pgDataDir} = {
    device = pgFs.device;
    fsType = pgFs.fsType;
    options = pgFs.options;
  };
}
