{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.acme_dns_api;
  dnsCfg = config.custom.services.authoritative_dns;
  domain = config.ogygia.domain;
  knotc = "${pkgs.knot-dns}/bin/knotc";

  # Extract IP from first Knot listen address (format: "IP@port")
  knotListenAddr = builtins.head (lib.strings.splitString "@"
    (builtins.head config.services.knot.settings.server.listen));

  # Perl script with required libraries
  acmeDnsApiScript = pkgs.writers.writePerlBin "acme-dns-api"
    {
      libraries = with pkgs.perlPackages; [
        HTTPDaemon
        JSON
        NetDNS
        CryptEd25519
        LWPUserAgent
      ];
    }
    (builtins.readFile ./acme-dns-api.pl);
in
{
  options.custom.services.acme_dns_api = {
    enable = lib.mkEnableOption "acme_dns_api";
  };

  config = lib.mkIf cfg.enable {
    # Requires authoritative DNS to be enabled on the same host
    assertions = [{
      assertion = dnsCfg.enable;
      message = "acme_dns_api requires authoritative_dns to be enabled";
    }];

    systemd.services.acme-dns-api = {
      description = "ACME DNS-01 Challenge API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "knot.service" ];

      script = "${acmeDnsApiScript}/bin/acme-dns-api";

      environment = {
        ACME_DNS_DOMAIN = domain;
        ACME_DNS_LISTEN_ADDR = config.custom.dns.nebula.ipv4;
        ACME_DNS_KNOTC = knotc;
        ACME_DNS_KNOT_NAMESERVER = knotListenAddr;
      };

      serviceConfig = {
        User = "knot";
        Group = "knot";
        Restart = "always";
        RestartSec = "5s";

        # Security hardening
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

  };
}
