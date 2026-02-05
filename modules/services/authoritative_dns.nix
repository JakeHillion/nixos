{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.authoritative_dns;
  domain = config.ogygia.domain;

  locations = config.custom.locations.locations;
  makeRecords = type: s: (lib.concatStringsSep "\n" (lib.collect builtins.isString (lib.mapAttrsRecursive (path: value: "${lib.concatStringsSep "." (lib.reverseList path)} 86400 ${type} ${value}") s)));

  zoneContent = ''
    $ORIGIN ${domain}.
    $TTL 86400

    ${domain}. IN SOA ns1.jakehillion.me. hostmaster.jakehillion.me. (
        1           ;Serial
        7200        ;Refresh
        3600        ;Retry
        1209600     ;Expire
        3600        ;Negative response caching TTL
    )

    @                                 86400 NS ns1.jakehillion.me.

    ca                                21600 CNAME warlock.cx.${domain}.
    frigate                           21600 CNAME ${locations.services.frigate}.
    homebox                           21600 CNAME ${locations.services.homebox}.
    immich                            21600 CNAME ${locations.services.immich}.
    ollama                            21600 CNAME ${locations.services.ollama}.
    privatebin                        21600 CNAME ${locations.services.privatebin}.
    prometheus                        21600 CNAME ${locations.services.prometheus}.
    radicale                          21600 CNAME ${locations.services.radicale}.
    restic                            21600 CNAME ${locations.services.restic}.
    status                            21600 CNAME ${locations.services.status}.
    wallpapers                        21600 CNAME phoenix.st.${domain}.

    mqtt.home                         21600 CNAME ${locations.services.mosquitto}.
    zigbee2mqtt.home                  21600 CNAME ${locations.services.zigbee2mqtt}.
    graphs.cyclone.gw                 21600 CNAME cyclone.gw.${domain}.

    argus.kvm                         21600 CNAME cyclone.gw.${domain}.
    charlie.kvm                       21600 CNAME cyclone.gw.${domain}.
    hammer.kvm                        21600 CNAME cyclone.gw.${domain}.
    kvm.phoenix.st                    21600 CNAME cyclone.gw.${domain}.

    cgit.git                          21600 CNAME ${locations.services.git}.

    deluge.downloads                  21600 CNAME ${locations.services.downloads}.
    prowlarr.downloads                21600 CNAME ${locations.services.downloads}.
    radarr.downloads                  21600 CNAME ${locations.services.downloads}.
    sonarr.downloads                  21600 CNAME ${locations.services.downloads}.

  '' + (makeRecords "A" config.custom.dns.authoritative.ipv4.me.jakehillion.neb);

  zoneFile = pkgs.writeText "${domain}.zone" zoneContent;
in
{
  options.custom.services.authoritative_dns = {
    enable = lib.mkEnableOption "authoritative_dns";

    domain = lib.mkOption {
      type = lib.types.str;
      default = domain;
      readOnly = true;
      description = "The domain served by this authoritative DNS server";
    };
  };

  config = lib.mkIf cfg.enable {
    services.knot = {
      enable = true;

      settings = {
        acl = [{
          id = "localhost";
          address = [ "127.0.0.1" "::1" ];
          action = [ "update" ];
        }];

        zone = [{
          domain = domain;
          file = zoneFile;
          acl = [ "localhost" ];
          # Don't sync changes back to the zone file (it's in the read-only Nix store)
          # Dynamic updates are kept in journal only
          zonefile-sync = -1;
          zonefile-load = "difference-no-serial";
          journal-content = "all";
        }];
      };
    };
  };
}
