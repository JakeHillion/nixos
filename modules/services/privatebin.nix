{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.privatebin;
in
{
  options.custom.services.privatebin = {
    enable = lib.mkEnableOption "privatebin";
  };

  config = lib.mkIf cfg.enable {
    users.users.privatebin.uid = config.ids.uids.privatebin;

    services.privatebin = {
      enable = true;
      group = "caddy";

      settings = {
        main = {
          name = "Hillion Pastebin";
          basepath = "https://pastes.hillion.co.uk";
          notice = "External users cannot submit pastes.";
        };

        expire.default = "1week";
        expire_options = {
          "10min" = "600";
          "1hour" = "3600";
          "1day" = "86400";
          "1week" = "604800";
          "1month" = "2592000";
          "1year" = "31536000";
        };
      };
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."privatebin.${config.ogygia.domain}".extraConfig = ''
        root * ${config.services.privatebin.package}
        encode gzip zstd

        @blockOutsiders {
          method POST
          not client_ip 172.20.0.0/24
        }
        respond @blockOutsiders "Forbidden" 403

        file_server
        php_fastcgi unix/${config.services.phpfpm.pools.privatebin.socket}
      '';
    };
  };
}
