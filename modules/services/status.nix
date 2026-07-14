{ config, lib, ... }:

let
  cfg = config.custom.services.status;
in
{
  options.custom.services.status = {
    enable = lib.mkEnableOption "status";
  };

  config = lib.mkIf cfg.enable {
    ogygia.dashboard = {
      enable = true;
      title = "Jake's Home Lab Status";
      serverConfig = { port = 47283; };
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."status.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:47283
      '';
    };
  };
}
