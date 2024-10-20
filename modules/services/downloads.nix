{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.downloads;
in
{
  options.custom.services.downloads = {
    enable = lib.mkEnableOption "downloads";

    metadataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/downloads";
    };
    downloadCachePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/torrents";
    };
    filmsPath = lib.mkOption {
      type = lib.types.str;
    };
    tvPath = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."wireguard/downloads".file = ../../secrets/wireguard/downloads.age;
    age.secrets."deluge/auth" = {
      file = ../../secrets/deluge/auth.age;
      owner = "deluge";
    };

    services.caddy = {
      enable = true;

      virtualHosts = builtins.listToAttrs (builtins.map
        (x: {
          name = "${x}.downloads.ts.hillion.co.uk";
          value = {
            listenAddresses = [ config.custom.dns.tailscale.ipv4 config.custom.dns.tailscale.ipv6 ];
            extraConfig = ''
              reverse_proxy unix//${cfg.metadataPath}/caddy/caddy.sock

              tls {
                ca https://ca.ts.hillion.co.uk:8443/acme/acme/directory
              }
            '';
          };
        }) [ "prowlarr" "sonarr" "radarr" "deluge" ]);
    };


    ## Wireguard
    networking.wireguard.interfaces."downloads" = {
      privateKeyFile = config.age.secrets."wireguard/downloads".path;
      ips = [ "10.2.0.2/32" ];
      peers = [
        {
          publicKey = "9nrcUUgwvjNU5Z+EBB0C2cbrhQ3dsCz+zSU83/eqGFY=";
          endpoint = "138.199.6.177:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
      interfaceNamespace = "downloads";
      preSetup = "test -f /run/netns/downloads || ip netns add downloads || test -f /run/netns/downloads";
    };

    ## Host User/Directories
    users.groups = {
      radarr.gid = config.ids.gids.radarr;
      deluge.gid = config.ids.gids.deluge;
      sonarr.gid = config.ids.gids.sonarr;
      mediaaccess = {
        gid = config.ids.gids.mediaaccess;
        members = [ "radarr" "sonarr" "deluge" config.custom.user ];
      };
    };
    users.users =
      let
        mkUser = user: {
          name = user;
          value = {
            group = user;
            home = "${cfg.metadataPath}/${user}";
            uid = config.ids.uids.${user};
            createHome = true;
          };
        };
        users = [ "radarr" "deluge" "sonarr" ];
      in
      builtins.listToAttrs (builtins.map mkUser users);

    systemd.tmpfiles.rules = [
      "d ${cfg.downloadCachePath} 0750 deluge mediaaccess - -"
      "d ${cfg.filmsPath} 0770 radarr mediaaccess - -"
      "d ${cfg.tvPath} 0770 sonarr mediaaccess - -"
    ];

    ## Container
    containers."downloads" = {
      autoStart = true;
      ephemeral = true;

      additionalCapabilities = [ "CAP_NET_ADMIN" ];
      extraFlags = [ "--network-namespace-path=/run/netns/downloads" ];

      bindMounts = {
        "/var/lib/caddy" = { hostPath = "${cfg.metadataPath}/caddy"; isReadOnly = false; };
        "/var/lib/sonarr" = { hostPath = "${cfg.metadataPath}/sonarr"; isReadOnly = false; };
        "/var/lib/radarr" = { hostPath = "${cfg.metadataPath}/radarr"; isReadOnly = false; };
        "/var/lib/deluge" = { hostPath = "${cfg.metadataPath}/deluge"; isReadOnly = false; };
        "/var/lib/private/prowlarr" = { hostPath = "${cfg.metadataPath}/prowlarr"; isReadOnly = false; };

        "/media/downloads" = { hostPath = cfg.downloadCachePath; isReadOnly = false; };
        "/media/films" = { hostPath = cfg.filmsPath; isReadOnly = false; };
        "/media/tv" = { hostPath = cfg.tvPath; isReadOnly = false; };

        "/run/agenix/deluge/auth".hostPath = config.age.secrets."deluge/auth".path;
      };

      config = (hostConfig: ({ config, pkgs, ... }: {
        config = {
          system.stateVersion = "23.05";

          ids = hostConfig.ids;

          users.groups.mediaaccess = {
            gid = config.ids.gids.mediaaccess;
            members = [ "radarr" "sonarr" "deluge" ];
          };

          systemd.services.setup-loopback = {
            description = "Setup container loopback adapter.";
            before = [ "network.target" ];

            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;

            script = with pkgs; "${iproute2}/bin/ip link set up lo";
          };
          networking = {
            nameservers = [ "1.1.1.1" "8.8.8.8" ];
            hosts = { "127.0.0.1" = builtins.map (x: "${x}.downloads.ts.hillion.co.uk") [ "prowlarr" "sonarr" "radarr" "deluge" ]; };
          };

          services = {
            prowlarr.enable = true;

            sonarr = {
              enable = true;
              dataDir = "/var/lib/sonarr";
            };
            radarr = {
              enable = true;
              dataDir = "/var/lib/radarr";
            };

            deluge = {
              enable = true;
              web.enable = true;
              group = "mediaaccess";

              dataDir = "/var/lib/deluge";
              authFile = "/run/agenix/deluge/auth";

              declarative = true;
              config = {
                download_location = "/media/downloads";
                max_connections_global = 1024;

                max_upload_speed = 12500;
                max_download_speed = 25000;

                max_active_seeding = 192;
                max_active_downloading = 64;
                max_active_limit = 256;
                dont_count_slow_torrents = true;

                stop_seed_at_ratio = true;
                stop_seed_ratio = 2;

                enabled_plugins = [ "Label" ];
              };
            };

            caddy = {
              enable = true;
              virtualHosts = builtins.listToAttrs (builtins.map
                (x: {
                  name = "http://${x.name}.downloads.ts.hillion.co.uk";
                  value = {
                    listenAddresses = [ "127.0.0.1" "unix///var/lib/caddy/caddy.sock" ];
                    extraConfig = "reverse_proxy http://localhost:${toString x.port}";
                  };
                }) [
                { name = "radarr"; port = 7878; }
                { name = "sonarr"; port = 8989; }
                { name = "prowlarr"; port = 9696; }
                { name = "deluge"; port = config.services.deluge.web.port; }
              ]);
            };
          };
        };
      })) config;
    };
  };
}
