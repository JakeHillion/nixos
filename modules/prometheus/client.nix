{ pkgs, lib, config, ... }:

let
  cfg = config.custom.prometheus.client;
in
{
  options.custom.prometheus.client = {
    enable = lib.mkEnableOption "prometheus-client";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      port = 9000;
    };
  };
}
