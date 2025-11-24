{ config, lib, ... }:

let
  cfg = config.custom.ogygia;
in
{
  options.custom.ogygia.enable = lib.mkEnableOption "ogygia";

  config = lib.mkIf cfg.enable {
    ogygia = {
      enable = true;
      domain = "neb.jakehillion.me";

      zookeeper = {
        enable = true;
        endpoints = config.custom.services.zookeeper.clientHosts;
      };
    };
  };
}
