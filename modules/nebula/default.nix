{ config, lib, pkgs, ... }:

let
  cfg = config.custom.nebula;

  lighthouses = {
    "boron.cx.${config.ogygia.domain}" = "boron.cx.jakehillion.me:4242";
    "cyclone.gw.${config.ogygia.domain}" = "home.jakehillion.me:4242";
    "li.pop.${config.ogygia.domain}" = "home.scott.hillion.co.uk:4242";
  };
  relays = [
    "boron.cx.${config.ogygia.domain}"
    "cyclone.gw.${config.ogygia.domain}"
  ];

  serviceUser = config.systemd.services."nebula@jakehillion".serviceConfig.User;
  serviceGroup = config.systemd.services."nebula@jakehillion".serviceConfig.Group;

  lookupIpv4 = fqdn: lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." fqdn)) null config.custom.dns.authoritative.ipv4;

  # Generate a nebula-online service for each configured network
  mkNebulaOnlineService = netName: netCfg:
    {
      name = "nebula-online@${netName}";
      value = {
        description = "Wait for Nebula interface ${netName} to be online";
        after = [ "nebula@${netName}.service" ];
        requires = [ "nebula@${netName}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "60";
        };
        script = ''
          until ${pkgs.iproute2}/bin/ip addr show "${netCfg.tun.device}" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "inet "; do
            sleep 1
          done
        '';
      };
    };
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

    forcePort = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Force Nebula to listen on port 4242 (useful for firewall rules on non-lighthouse hosts)";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users."nebula-jakehillion".uid = config.ids.uids."nebula-jakehillion";
    users.groups."nebula-jakehillion".gid = config.ids.gids."nebula-jakehillion";

    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.certPath} 0775 ${serviceUser} ${serviceGroup} - -"
      "d ${builtins.dirOf cfg.keyPath} 0775 ${serviceUser} ${serviceGroup} - -"
    ];
    systemd.services = lib.attrsets.mapAttrs' mkNebulaOnlineService config.services.nebula.networks // {
      generate-nebula-certs = {
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

          listen = lib.mkMerge [
            { host = "[::]"; }

            (lib.mkIf (isLighthouse || cfg.forcePort) {
              port = 4242;
            })
          ];

          staticHostMap = lib.attrsets.mapAttrs' (name: value: lib.attrsets.nameValuePair (lookupIpv4 name) [ value ]) lighthouses;

          settings = {
            lighthouse = {
              remote_allow_list = {
                # block peering over Tailscale IPs
                "100.64.0.0/10" = false;
                "fd7a:115c:a1e0::/48" = false;
              };
            };

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
            outbound = [{ host = "any"; port = "any"; proto = "any"; }];
            inbound = [
              { groups = [ "legacy-full-access" ]; port = "any"; proto = "any"; }
            ];
          };
        };
      };
  };
}
