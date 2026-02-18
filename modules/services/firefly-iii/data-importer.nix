{ config, lib, ... }:

let
  cfg = config.custom.services.firefly-iii-data-importer;
in
{
  options.custom.services.firefly-iii-data-importer = {
    enable = lib.mkEnableOption "firefly-iii-data-importer";
  };

  config = lib.mkIf cfg.enable {
    users.users.firefly-iii-data-importer.uid = config.ids.uids.firefly-iii-data-importer;

    age.secrets."firefly-iii/access-token" = {
      file = ./access-token.age;
      owner = "firefly-iii-data-importer";
      group = "caddy";
    };

    services.firefly-iii-data-importer.dataDir = lib.mkIf config.custom.impermanence.enable
      "${config.custom.impermanence.base}/services/firefly-iii-data-importer";

    custom.www.nebula = {
      enable = true;
      virtualHosts."firefly-importer.${config.ogygia.domain}" = {
        extraConfig = ''
          root * ${config.services.firefly-iii-data-importer.package}/public
          php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii-data-importer.socket}
          file_server
        '';
      };
    };

    # Upstream module is missing storage/import-jobs from tmpfiles
    systemd.tmpfiles.settings."10-firefly-iii-data-importer"."${config.services.firefly-iii-data-importer.dataDir}/storage/import-jobs".d = {
      group = config.services.firefly-iii-data-importer.group;
      mode = "0710";
      user = config.services.firefly-iii-data-importer.user;
    };

    services.firefly-iii-data-importer = {
      enable = true;
      group = "caddy";
      settings = {
        FIREFLY_III_URL = "https://firefly.${config.ogygia.domain}";
        FIREFLY_III_ACCESS_TOKEN_FILE = config.age.secrets."firefly-iii/access-token".path;
      };
    };
  };
}
