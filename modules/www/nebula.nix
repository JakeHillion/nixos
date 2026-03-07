{ config, lib, pkgs, ... }:

let
  cfg = config.custom.www.nebula;
  locations = config.custom.locations.locations;

  # The ACME DNS API host - use the first authoritative_dns host
  acmeApiHost =
    let
      authDns = locations.services.authoritative_dns;
    in
    if builtins.isList authDns then builtins.head authDns else authDns;

  nebulaIp = config.custom.dns.nebula.ipv4;

  # Script to generate ED25519 keypair for ACME DNS authentication
  generateAcmeKeys = pkgs.writeShellScript "generate-acme-keys" ''
    set -euo pipefail

    KEY_DIR="/run/caddy-nebula-acme"
    PRIVATE_KEY="$KEY_DIR/private.key"
    PUBLIC_KEY="$KEY_DIR/public.key"

    # Check if keys already exist
    if [[ -f "$PRIVATE_KEY" && -f "$PUBLIC_KEY" ]]; then
      exit 0
    fi

    ${pkgs.openssl}/bin/openssl genpkey -algorithm ed25519 -out "$PRIVATE_KEY"
    ${pkgs.openssl}/bin/openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"

    chmod 600 "$PRIVATE_KEY"
    chmod 644 "$PUBLIC_KEY"
  '';
in
{
  options.custom.www.nebula = {
    enable = lib.mkEnableOption "caddy-nebula";
    virtualHosts = lib.mkOption {
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      globalConfig = ''
        servers {
        	trusted_proxies static 172.20.0.0/24
        }
        email acme@jakehillion.me
      '';

      virtualHosts = lib.attrsets.mapAttrs
        (name: value: (value // {
          listenAddresses = [ nebulaIp ];
          extraConfig = ''
            tls {
              dns jakehillion {
                api_endpoint http://${acmeApiHost}:8553
                key_path /run/caddy-nebula-acme
              }
            }
          '' + value.extraConfig;
        }))
        cfg.virtualHosts
      # Serve ACME DNS public key on HTTP
      // {
        "http://${nebulaIp}" = {
          listenAddresses = [ nebulaIp ];
          extraConfig = ''
            handle /.well-known/acme-dns-key {
              file_server {
                root /run/caddy-nebula-acme
              }
              rewrite /.well-known/acme-dns-key /public.key
            }
            handle {
              respond "Not found" 404
            }
          '';
        };
      };
    };

    systemd.services.caddy = {
      after = [ "nebula-online@jakehillion.service" ];
      requires = [ "nebula-online@jakehillion.service" ];

      serviceConfig = {
        RuntimeDirectory = "caddy-nebula-acme";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = generateAcmeKeys;
      };
    };
  };
}
