{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.hearthd;

  # Secrets managed via agenix-rekey. Each entry registers an
  # age.secrets."hearthd/<name>".rekeyFile pointing at <name>.age, and its
  # decrypted path is appended to services.hearthd.secretConfigs below.
  rekeySecrets = [ "ecoflow.toml" ];

  acmeApiHost =
    let
      authDns = config.custom.locations.locations.services.authoritative_dns;
    in
    if builtins.isList authDns then builtins.head authDns else authDns;

  # IoT clients permitted to reach the hearthd vhost.
  hearthdAllowedClients = [
    "10.239.19.16" # bedroom-portal
  ];

  # Portal dashboard server: serves /state and /template/<hash> for Portals,
  # pulling live light state from the colocated hearthd. Exposed on the IoT
  # vhost under /extra/portals/ (see caddy below).
  portalsPort = 8566;

  # Portal screensavers are pre-rendered from Apple dynamic-desktop HEICs held on
  # the NAS (wallpapers.${domain}). Each HEIC packs every time-of-day frame into
  # one >100 MiB container; the Portals are tiny, so we render each frame to a
  # 1280x800 JPEG and emit per-frame sun-elevation metadata, served read-only
  # under /static/screensavers/<slug>/ (see caddy below) so the Portal never
  # touches the HEICs. To add or drop a wallpaper, edit this set;
  # `nix store prefetch-file <url>` gives the hash.
  wallpaperBaseUrl = "https://wallpapers.${config.ogygia.domain}/JetsonCreative/24_Hour_Naturescapes";
  wallpapers = {
    "canyonlands" = { file = "24hr-Canyonlands-2.heic"; sha256 = "1d07b3df6702a2ac87709096658a05a29805c8e9c142fec74d97a1b1faddd755"; };
    "catalina-little-harbor" = { file = "24hr-CatalinaLittleHarbor.heic"; sha256 = "472b7defddd3435cca5f28927dd90b95131a0ffcecd29ddc52c9015e674baa4c"; };
    "glacier" = { file = "24hr-Glacier.heic"; sha256 = "ab2e8fa11cc6f94f25738842419baf7e48c182bbd74fd35d66c4284fe129a65a"; };
    "yosemite-lukens" = { file = "24hr-YosemiteLukens.heic"; sha256 = "5f5890445b61448ebc5eb025cc34af9aa58e365f3545ee9f08be1912ae901687"; };
    "oxenhope" = { file = "24hr-Oxenhope.heic"; sha256 = "fcbdeb306b64cff674b0d9cb61b7cc0bf1d12518294d50b04a99d53930b4fd13"; };
    "joshua-tree" = { file = "24hr-JoshuaTree.heic"; sha256 = "df8a33d880022f6c5220a225d1cc3113f6b45d8f4ab801a5f7a4fddd3170205a"; };
  };

  renderWallpaper = name: w: ''
    python3 ${./screensavers/build.py} ${pkgs.fetchurl {
      url = "${wallpaperBaseUrl}/${w.file}";
      inherit (w) sha256;
    }} "$out/${name}"
  '';

  screensavers = pkgs.runCommand "hearthd-screensavers"
    {
      nativeBuildInputs = [ pkgs.imagemagick pkgs.exiftool pkgs.python3 ];
    } ''
    mkdir -p "$out"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderWallpaper wallpapers)}
  '';
in
{
  options.custom.services.hearthd = {
    enable = lib.mkEnableOption "hearthd";
  };

  config = lib.mkIf cfg.enable {
    age.secrets = lib.mkMerge [
      (builtins.listToAttrs (map
        (name: {
          name = "hearthd/${name}";
          value.rekeyFile = ./. + "/${name}.age";
        })
        rekeySecrets))
      {
        "hearthd/locations.toml".file = ./locations.toml.age;
        "hearthd/mqtt.toml".file = ./mqtt.toml.age;
      }
    ];

    # The caddy vhost below solves DNS-01 challenges against the acme-dns-api on
    # ${acmeApiHost}:8553 over Nebula. Grant that path at the point of use so it
    # doesn't depend on the broad legacy-full-access group (see modules/www/nebula.nix).
    ogygia.nebula.groups = [ "acme-dns-client" ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."hearthd.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:8565
      '';
    };

    services.caddy = {
      enable = true;

      virtualHosts."hearthd.iot.home.jakehillion.me" = {
        listenAddresses = [ "10.239.19.8" ];
        extraConfig = ''
          tls {
            dns jakehillion {
              api_endpoint http://${acmeApiHost}:8553
            }
          }

          @blocked not remote_ip ${lib.concatStringsSep " " hearthdAllowedClients}
          respond @blocked "<h1>Access Denied</h1>" 403

          handle_path /extra/portals/* {
            reverse_proxy http://127.0.0.1:${toString portalsPort}
          }

          handle_path /static/screensavers/* {
            root * ${screensavers}
            file_server
          }

          handle {
            reverse_proxy http://127.0.0.1:8565
          }
        '';
      };
    };

    systemd.services.hearthd-portals = {
      description = "hearthd portal dashboard server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "hearthd.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./portals/serve.py} ${./portals/template.json} --host 127.0.0.1 --port ${toString portalsPort} --hearthd http://127.0.0.1:8565";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;

        # Hardening: the server reads only its Nix-store template and talks to
        # the local hearthd over loopback, so lock everything else down.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };

    services.hearthd = {
      enable = true;

      secretConfigs =
        (map (name: config.age.secrets."hearthd/${name}".path) rekeySecrets)
        ++ (with config.age; [
          secrets."hearthd/locations.toml".path
          secrets."hearthd/mqtt.toml".path
        ]);
      config = {
        logging = {
          level = "info";
          overrides = {
            "hearthd" = "debug";
          };
        };

        locations.default = "home";

        http = {
          listen = "127.0.0.1";
          port = 8565;
        };

        integrations.mqtt = {
          broker = "mqtt.home.${config.ogygia.domain}";
          port = 1883;
          client_id = "hearthd";
          discovery_prefix = "homeassistant";
          username = "hearthd";
        };

        integrations.metno = {
          locations = [ "home" ];
        };

        # snapcast and hearthd are colocated on this host, but snapserver's
        # control interface is bound to the Nebula IP (so the phone can reach it
        # too), so connect to that address rather than loopback.
        integrations.snapcast = {
          host = config.custom.dns.nebula.ipv4;
          port = 1705;
        };
      };
    };
  };
}
