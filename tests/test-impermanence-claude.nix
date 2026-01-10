# Test Claude persistence - verifies mounts and tmpfiles
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
      custom.home.claude.enable = true;
    }];
  };

  # Extract just the essential mount info
  simplifyMount = m: { what = m.what; where = m.where; };

in
{
  systemd.mounts = map simplifyMount config.config.systemd.mounts;
  systemd.tmpfiles.rules = config.config.systemd.tmpfiles.rules;
}
