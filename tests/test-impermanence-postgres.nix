# Test PostgreSQL persistence - verifies mounts
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
      services.postgresql.enable = true;
    }];
  };

  # Extract just the essential mount info
  simplifyMount = m: { what = m.what; where = m.where; };

in
{
  systemd.mounts = map simplifyMount config.config.systemd.mounts;
}
