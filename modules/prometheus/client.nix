{ pkgs, lib, config, ... }:

let
  cfg = config.custom.prometheus.client;
in
{
  options.custom.prometheus.client = {
    enable = lib.mkEnableOption "prometheus-client";
  };

  config = lib.mkIf cfg.enable {
    users.users.node-exporter.uid = config.ids.uids.node-exporter;
    users.groups.node-exporter.gid = config.ids.gids.node-exporter;

    services.prometheus.exporters.node = {
      enable = true;
      port = 9000;

      enabledCollectors = [
        "systemd"
      ];
    };
  };
}
