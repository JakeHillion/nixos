{ config, pkgs, lib, ... }:

let
  cfg = config.custom.ca.service;
in
{
  options.custom.ca.service = {
    enable = lib.mkEnableOption "ca.service";
  };

  config = lib.mkIf cfg.enable {
    custom.impermanence.directories = lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/step-ca" ];

    users.users.step-ca.uid = config.ids.uids.step-ca;
    users.groups.step-ca.gid = config.ids.gids.step-ca;

    services.step-ca = {
      enable = true;

      address = config.custom.dns.nebula.ipv4;
      port = 8443;

      intermediatePasswordFile = "/data/system/ca/intermediate.psk";

      settings = {
        root = ./cert.pem;
        crt = "/data/system/ca/intermediate.crt";
        key = "/data/system/ca/intermediate.pem";

        dnsNames = [ "ca.${config.ogygia.domain}" ];

        logger = { format = "text"; };

        db = {
          type = "badgerv2";
          dataSource = "/var/lib/private/step-ca/db";
        };

        authority = {
          provisioners = [
            {
              type = "ACME";
              name = "acme";
            }
          ];
        };
      };
    };
  };
}
