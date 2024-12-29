{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.authoritative_dns;
in
{
  options.custom.services.authoritative_dns = {
    enable = lib.mkEnableOption "authoritative_dns";
  };

  config = lib.mkIf cfg.enable {
    services.nsd = {
      enable = true;

      zones =
        let
          locations = config.custom.locations.locations;
          makeRecords = type: s: (lib.concatStringsSep "\n" (lib.collect builtins.isString (lib.mapAttrsRecursive (path: value: "${lib.concatStringsSep "." (lib.reverseList path)} 86400 ${type} ${value}") s)));
        in
        {
          "ts.hillion.co.uk".data = ''
            $ORIGIN ts.hillion.co.uk.
            $TTL 86400

            ts.hillion.co.uk. IN SOA ns1.hillion.co.uk. hostmaster.hillion.co.uk. (
                1           ;Serial
                7200        ;Refresh
                3600        ;Retry
                1209600     ;Expire
                3600        ;Negative response caching TTL
            )

            86400 NS ns1.hillion.co.uk.
            86400 NS ns2.hillion.co.uk.

          '' + (makeRecords "A" config.custom.dns.authoritative.ipv4.uk.co.hillion.ts) + "\n\n" + (makeRecords "AAAA" config.custom.dns.authoritative.ipv6.uk.co.hillion.ts);

          "neb.jakehillion.me".data = ''
            $ORIGIN neb.jakehillion.me.
            $TTL 86400

            neb.jakehillion.me. IN SOA ns1.jakehillion.me. hostmaster.jakehillion.me. (
                1           ;Serial
                7200        ;Refresh
                3600        ;Retry
                1209600     ;Expire
                3600        ;Negative response caching TTL
            )

            86400 NS ns1.jakehillion.me.
            86400 NS ns2.jakehillion.me.

            ca                    21600 CNAME sodium.pop.neb.jakehillion.me.
            frigate               21600 CNAME ${locations.services.frigate}.
            immich                21600 CNAME ${locations.services.immich}.
            prometheus            21600 CNAME ${locations.services.prometheus}.
            restic                21600 CNAME ${locations.services.restic}.

            zigbee2mqtt.home      21600 CNAME router.home.neb.jakehillion.me.
            graphs.router.home    21600 CNAME router.home.neb.jakehillion.me.

            charlie.kvm           21600 CNAME router.home.neb.jakehillion.me.
            hammer.kvm            21600 CNAME router.home.neb.jakehillion.me.

            deluge.downloads      21600 CNAME ${locations.services.downloads}.
            prowlarr.downloads    21600 CNAME ${locations.services.downloads}.
            radarr.downloads      21600 CNAME ${locations.services.downloads}.
            sonarr.downloads      21600 CNAME ${locations.services.downloads}.

          '' + (makeRecords "A" config.custom.dns.authoritative.ipv4.me.jakehillion.neb);
        };
    };
  };
}

