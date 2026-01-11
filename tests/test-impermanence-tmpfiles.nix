# Impermanence tmpfiles.rules snapshot test
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
  systemd.tmpfiles.rules = config.config.systemd.tmpfiles.rules;
}
