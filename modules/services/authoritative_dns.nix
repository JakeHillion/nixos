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

      zones = {
        "ts.hillion.co.uk" = {
          data =
            let
              makeRecords = type: s: (lib.concatStringsSep "\n" (lib.collect builtins.isString (lib.mapAttrsRecursive (path: value: "${lib.concatStringsSep "." (lib.reverseList path)} 86400 ${type} ${value}") s)));
            in
            ''
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

              ca                    21600 CNAME sodium.pop.ts.hillion.co.uk.
              restic                21600 CNAME ${config.custom.locations.locations.services.restic}.
              prometheus            21600 CNAME ${config.custom.locations.locations.services.prometheus}.

              deluge.downloads      21600 CNAME ${config.custom.locations.locations.services.downloads}.
              prowlarr.downloads    21600 CNAME ${config.custom.locations.locations.services.downloads}.
              radarr.downloads      21600 CNAME ${config.custom.locations.locations.services.downloads}.
              sonarr.downloads      21600 CNAME ${config.custom.locations.locations.services.downloads}.

              graphs.router.home    21600 CNAME router.home.ts.hillion.co.uk.
              zigbee2mqtt.home      21600 CNAME router.home.ts.hillion.co.uk.

              charlie.kvm           21600 CNAME router.home.ts.hillion.co.uk.
              hammer.kvm            21600 CNAME router.home.ts.hillion.co.uk.

            '' + (makeRecords "A" config.custom.dns.authoritative.ipv4.uk.co.hillion.ts) + "\n\n" + (makeRecords "AAAA" config.custom.dns.authoritative.ipv6.uk.co.hillion.ts);
        };
      };
    };
  };
}

