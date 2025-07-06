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

            attic                             21600 CNAME ${locations.services.attic}.
            ca                                21600 CNAME warlock.cx.neb.jakehillion.me.
            frigate                           21600 CNAME ${locations.services.frigate}.
            immich                            21600 CNAME ${locations.services.immich}.
            ollama                            21600 CNAME ${locations.services.ollama}.
            privatebin                        21600 CNAME ${locations.services.privatebin}.
            prometheus                        21600 CNAME ${locations.services.prometheus}.
            radicale                          21600 CNAME ${locations.services.radicale}.
            restic                            21600 CNAME ${locations.services.restic}.
            status                            21600 CNAME ${locations.services.status}.
            wallpapers                        21600 CNAME phoenix.st.neb.jakehillion.me.

            mqtt.home                         21600 CNAME ${locations.services.mosquitto}.
            zigbee2mqtt.home                  21600 CNAME router.home.neb.jakehillion.me.
            graphs.cyclone.gw                 21600 CNAME cyclone.gw.neb.jakehillion.me.

            charlie.kvm                       21600 CNAME cyclone.gw.neb.jakehillion.me.
            hammer.kvm                        21600 CNAME cyclone.gw.neb.jakehillion.me.
            kvm.phoenix.st                    21600 CNAME cyclone.gw.neb.jakehillion.me.

            deluge.downloads                  21600 CNAME ${locations.services.downloads}.
            prowlarr.downloads                21600 CNAME ${locations.services.downloads}.
            radarr.downloads                  21600 CNAME ${locations.services.downloads}.
            sonarr.downloads                  21600 CNAME ${locations.services.downloads}.

          '' + (makeRecords "A" config.custom.dns.authoritative.ipv4.me.jakehillion.neb);
        };
    };
  };
}

