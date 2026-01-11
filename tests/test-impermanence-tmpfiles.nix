# Impermanence tmpfiles.rules snapshot test
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
    }];
  };

  # Filter to just impermanence-generated rules
  isImpermanenceRule = rule:
    lib.hasPrefix "d /data/users" rule ||
    (lib.hasPrefix "L /" rule && lib.hasInfix "/local" rule);

in
{
  systemd.tmpfiles.rules = lib.filter isImpermanenceRule config.config.systemd.tmpfiles.rules;
}
