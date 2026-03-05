{ config, lib, ... }:

let
  cfg = config.custom.services.couchdb;
in
{
  options.custom.services.couchdb = {
    enable = lib.mkEnableOption "couchdb";
  };

  config = lib.mkIf cfg.enable {
    services.couchdb = {
      enable = true;
      databaseDir = lib.mkIf config.custom.impermanence.enable
        "${config.custom.impermanence.base}/services/couchdb/data";
      viewIndexDir = lib.mkIf config.custom.impermanence.enable
        "${config.custom.impermanence.base}/services/couchdb/views";
      configFile = lib.mkIf config.custom.impermanence.enable
        "${config.custom.impermanence.base}/services/couchdb/local.ini";
      extraConfig = {
        couchdb = {
          file_compression = "none";
        };
      };
      extraConfigFiles = [
        config.age.secrets."couchdb/admin".path
      ];
    };

    age.secrets."couchdb/admin" = {
      file = ./admin.age;
      owner = "couchdb";
      group = "couchdb";
    };

    systemd.tmpfiles.rules = lib.mkIf config.custom.impermanence.enable [
      "d ${config.custom.impermanence.base}/services/couchdb 0750 couchdb couchdb - -"
      "d ${config.custom.impermanence.base}/services/couchdb/data 0750 couchdb couchdb - -"
      "d ${config.custom.impermanence.base}/services/couchdb/views 0750 couchdb couchdb - -"
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."couchdb.${config.ogygia.domain}" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString config.services.couchdb.port}
        '';
      };
    };
  };
}
