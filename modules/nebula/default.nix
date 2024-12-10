{ config, lib, pkgs, ... }:

let
  cfg = config.custom.nebula;

  hostMatch = query: match:
    ((lib.concatStringsSep "." (lib.take 2 (lib.splitString "." query))) + ".neb.jakehillion.me") == match;

  lighthouses = {
    "boron.cx.neb.jakehillion.me" = "boron.cx.jakehillion.me:4242";
  };
  relays = [
    "boron.cx.neb.jakehillion.me"
  ];

  serviceUser = config.systemd.services."nebula@jakehillion".serviceConfig.User;
  serviceGroup = config.systemd.services."nebula@jakehillion".serviceConfig.Group;

  lookupIpv4 = fqdn: lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." fqdn)) null config.custom.dns.authoritative.ipv4;
in
{
  options.custom.nebula = {
    enable = lib.mkEnableOption "nebula";

    lighthouse = lib.mkEnableOption "nebula.lighthouse";
    relay = lib.mkEnableOption "nebula.relay";

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

    services.nebula.networks =
      let
        isLighthouse = lib.lists.any (x: hostMatch config.networking.fqdn x) (builtins.attrNames lighthouses);
        isRelay = lib.lists.any (x: hostMatch config.networking.fqdn x) relays;
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

          firewall = {
            inbound = [{ host = "any"; port = "any"; proto = "any"; }];
            outbound = [{ host = "any"; port = "any"; proto = "any"; }];
          };
        };
      };
  };
}
