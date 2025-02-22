{ config, lib, pkgs, ... }:

let
  cfg = config.custom.nebula;

  lighthouses = {
    "boron.cx.neb.jakehillion.me" = "boron.cx.jakehillion.me:4242";
    "li.pop.neb.jakehillion.me" = "home.scott.hillion.co.uk:4242";
    "router.home.neb.jakehillion.me" = "home.jakehillion.me:4242";
  };
  relays = [
    "router.home.neb.jakehillion.me"
    "boron.cx.neb.jakehillion.me"
  ];

  serviceUser = config.systemd.services."nebula@jakehillion".serviceConfig.User;
  serviceGroup = config.systemd.services."nebula@jakehillion".serviceConfig.Group;

  lookupIpv4 = fqdn: lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." fqdn)) null config.custom.dns.authoritative.ipv4;
in
{
  options.custom.nebula = {
    enable = lib.mkEnableOption "nebula";

    certPath = lib.mkOption {
      type = lib.types.str;
      default = "/data/nebula/host.crt";
    };
    keyPath = lib.mkOption {
      type = lib.types.str;
      default = "/data/nebula/host.key";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users."nebula-jakehillion".uid = config.ids.uids."nebula-jakehillion";
    users.groups."nebula-jakehillion".gid = config.ids.gids."nebula-jakehillion";

    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.certPath} 0775 ${serviceUser} ${serviceGroup} - -"
      "d ${builtins.dirOf cfg.keyPath} 0775 ${serviceUser} ${serviceGroup} - -"
    ];
    systemd.services.generate-nebula-certs = {
      description = "Generate empty Nebula certificates if they don't exist";

      before = [ "nebula@jakehillion.service" ];
      wantedBy = [ "multi-user.target" ];

      script = ''
        if [ ! -e ${cfg.certPath} ] && [ ! -e ${cfg.keyPath} ]; then
          ${pkgs.nebula}/bin/nebula-cert keygen -out-key ${cfg.keyPath} -out-pub ${cfg.certPath}
        fi

        chown ${serviceUser}:${serviceGroup} ${cfg.keyPath} ${cfg.certPath}
        chmod 0400 ${cfg.keyPath}
        chmod 0444 ${cfg.certPath}
      '';
    };

    # Turn off the normal firewall and use the Nebula capability based firewall instead.
    networking.firewall.trustedInterfaces = [ "neb.jh" ];

    services.nebula.networks =
      let
        isLighthouse = lib.lists.any (x: config.networking.fqdn == x) (builtins.attrNames lighthouses);
        isRelay = lib.lists.any (x: config.networking.fqdn == x) relays;
      in
      {
        "jakehillion" = {
          enable = true;
          tun.device = "neb.jh";

          ca = ./ca.crt;
          cert = cfg.certPath;
          key = cfg.keyPath;

          inherit isLighthouse isRelay;

          lighthouses = lib.lists.optionals (!isLighthouse) (builtins.map lookupIpv4 (builtins.attrNames lighthouses));
          relays = lib.lists.optionals (!isRelay) (builtins.map lookupIpv4 relays);

          staticHostMap = lib.attrsets.mapAttrs' (name: value: lib.attrsets.nameValuePair (lookupIpv4 name) [ value ]) lighthouses;

          settings = {
            stats = {
              type = "prometheus";
              namespace = "nebula";

              interval = "60s";
              listen = "${config.custom.dns.nebula.ipv4}:9001";
              path = "/metrics";

              message_metrics = true;
              lighthouse_metrics = true;
            };
          };

          firewall = {
            inbound = [{ host = "any"; port = "any"; proto = "any"; }];
            outbound = [{ host = "any"; port = "any"; proto = "any"; }];
          };
        };
      };
  };
}
