{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.authoritative_dns;
  domain = config.ogygia.domain;

  locations = config.custom.locations.locations;
  makeRecords = type: s: (lib.concatStringsSep "\n" (lib.collect builtins.isString (lib.mapAttrsRecursive (path: value: "${lib.concatStringsSep "." (lib.reverseList path)} 86400 ${type} ${value}") s)));

  # Role derivation from locations
  allHosts = locations.services.authoritative_dns;
  primaryHost = builtins.head allHosts;
  secondaryHosts = builtins.tail allHosts;
  isPrimary = config.networking.fqdn == primaryHost;
  isSecondary = builtins.elem config.networking.fqdn secondaryHosts;

  lookupFqdn = fqdn:
    lib.attrsets.attrByPath
      (lib.reverseList (lib.splitString "." fqdn))
      null
      config.custom.dns.authoritative.ipv4;

  primaryNebulaIp = lookupFqdn primaryHost;
  secondaryNebulaIps = map lookupFqdn secondaryHosts;

  # Generate remote definitions for secondaries (used on primary)
  secondaryRemotes = lib.imap0
    (i: ip: {
      id = "secondary${toString i}";
      address = "${ip}@53";
    })
    secondaryNebulaIps;
  secondaryRemoteIds = map (r: r.id) secondaryRemotes;

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
    @                                 86400 NS ns2.jakehillion.me.
    @                                 86400 NS ns3.jakehillion.me.

    ca                                21600 CNAME warlock.cx.${domain}.
    couchdb                           21600 CNAME ${locations.services.couchdb}.
    firefly                           21600 CNAME ${locations.services.firefly-iii}.
    firefly-importer                  21600 CNAME ${locations.services.firefly-iii-data-importer}.
    frigate                           21600 CNAME ${locations.services.frigate}.
    homebox                           21600 CNAME ${locations.services.homebox}.
    immich                            21600 CNAME ${locations.services.immich}.
    ollama                            21600 CNAME ${locations.services.ollama}.
    openwebui                         21600 CNAME ${locations.services.openwebui}.
    privatebin                        21600 CNAME ${locations.services.privatebin}.
    prometheus                        21600 CNAME ${locations.services.prometheus}.
    radicale                          21600 CNAME ${locations.services.radicale}.
    restic                            21600 CNAME ${locations.services.restic}.
    searxng                           21600 CNAME ${locations.services.searxng}.
    status                            21600 CNAME ${locations.services.status}.
    wallpapers                        21600 CNAME phoenix.st.${domain}.

    mqtt.home                         21600 CNAME ${locations.services.mosquitto}.
    zigbee2mqtt.home                  21600 CNAME ${locations.services.zigbee2mqtt}.

    argus.kvm                         21600 CNAME cyclone.gw.${domain}.
    charlie.kvm                       21600 CNAME cyclone.gw.${domain}.
    hammer.kvm                         21600 CNAME cyclone.gw.${domain}.
    kvm.phoenix.st                    21600 CNAME cyclone.gw.${domain}.

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

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Common config (both primary and secondary)
    {
      custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/knot" ];

      services.knot = {
        enable = true;

        settings = {
          server.listen = [ "${config.custom.dns.nebula.ipv4}@53" ];
        };
      };

      systemd.services.knot = {
        after = [ "nebula-online@jakehillion.service" ];
        requires = [ "nebula-online@jakehillion.service" ];
      };
    }

    # Primary config
    (lib.mkIf isPrimary {
      services.knot.settings = {
        remote = secondaryRemotes;

        acl = [
          {
            id = "localhost";
            address = [ "127.0.0.1" "::1" ];
            action = [ "update" ];
          }
          {
            id = "transfer_secondaries";
            address = secondaryNebulaIps;
            action = [ "transfer" ];
          }
        ];

        policy = [{
          id = "default";
          algorithm = "ecdsap256sha256";
          ksk-lifetime = 0;
          zsk-lifetime = 0;
        }];

        zone = [{
          domain = domain;
          file = zoneFile;
          acl = [ "localhost" "transfer_secondaries" ];
          notify = secondaryRemoteIds;
          # Don't sync changes back to the zone file (it's in the read-only Nix store)
          # Dynamic updates are kept in journal only
          zonefile-sync = -1;
          zonefile-load = "difference-no-serial";
          journal-content = "all";
          dnssec-signing = true;
          dnssec-policy = "default";
        }];
      };
    })

    # Secondary config
    (lib.mkIf isSecondary {
      services.knot.settings = {
        remote = [{
          id = "primary";
          address = "${primaryNebulaIp}@53";
        }];

        acl = [{
          id = "notify_primary";
          address = [ primaryNebulaIp ];
          action = [ "notify" ];
        }];

        zone = [{
          domain = domain;
          master = [ "primary" ];
          acl = [ "notify_primary" ];
          zonefile-sync = -1;
          journal-content = "all";
        }];
      };
    })
  ]);
}
