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
    age.secrets."downloads/wireguard".file = ./wireguard.age;
    age.secrets."downloads/deluge_auth" = {
      file = ./deluge_auth.age;
      owner = "deluge";
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts = builtins.listToAttrs (builtins.map
        (x: {
          name = "${x}.downloads.${config.ogygia.domain}";
          value = {
            extraConfig = ''
              reverse_proxy unix//${cfg.metadataPath}/caddy/caddy.sock
            '';
          };
        }) [ "prowlarr" "sonarr" "radarr" "deluge" ]);
    };


    ## Wireguard
    networking.wireguard.interfaces."downloads" = {
      privateKeyFile = config.age.secrets."downloads/wireguard".path;
      ips = [ "10.2.0.2/32" ];
      peers = [
        {
          publicKey = "Ii6hAbnu84wZ8NzVt5+ylO4FnX+ANrKNzpFOSYq9dks=";
          endpoint = "79.127.184.216:51820";
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
      extraFlags = [
        "--resolv-conf=off"
        "--network-namespace-path=/run/netns/downloads"
      ];
      # copyResolvConf = false; # Temporarily commented out - upstreaming in https://github.com/NixOS/nixpkgs/pull/450979

      bindMounts = {
        "/var/lib/caddy" = { hostPath = "${cfg.metadataPath}/caddy"; isReadOnly = false; };
        "/var/lib/sonarr" = { hostPath = "${cfg.metadataPath}/sonarr"; isReadOnly = false; };
        "/var/lib/radarr" = { hostPath = "${cfg.metadataPath}/radarr"; isReadOnly = false; };
        "/var/lib/deluge" = { hostPath = "${cfg.metadataPath}/deluge"; isReadOnly = false; };
        "/var/lib/private/prowlarr" = { hostPath = "${cfg.metadataPath}/prowlarr"; isReadOnly = false; };

        "/media/downloads" = { hostPath = cfg.downloadCachePath; isReadOnly = false; };
        "/media/films" = { hostPath = cfg.filmsPath; isReadOnly = false; };
        "/media/tv" = { hostPath = cfg.tvPath; isReadOnly = false; };

        "/run/agenix/downloads/deluge_auth".hostPath = config.age.secrets."downloads/deluge_auth".path;
      };

      config = (hostConfig: ({ config, pkgs, ... }: {
        config = {
          # TODO: remove me as soon as the Arrs are compatible with a newer version
          nixpkgs.config.permittedInsecurePackages = [
            "aspnetcore-runtime-6.0.36"
            "aspnetcore-runtime-wrapped-6.0.36"
            "dotnet-sdk-wrapped-6.0.428"
            "dotnet-sdk-6.0.428"
          ];

          system.stateVersion = "23.05";

          ids = hostConfig.ids;

          users.groups.mediaaccess = {
            gid = config.ids.gids.mediaaccess;
            members = [ "radarr" "sonarr" "deluge" ];
          };

          networking = {
            firewall.enable = false; # interferes with NAT-PMP
            nameservers = [ "1.1.1.1" "8.8.8.8" ];
            hosts = { "127.0.0.1" = builtins.map (x: "${x}.downloads.${hostConfig.ogygia.domain}") [ "prowlarr" "sonarr" "radarr" "deluge" ]; };
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
              authFile = "/run/agenix/downloads/deluge_auth";

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
                  name = "http://${x.name}.downloads.${hostConfig.ogygia.domain}";
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

          systemd.services = {
            setup-loopback = {
              description = "Setup container loopback adapter.";
              before = [ "network.target" ];

              serviceConfig.Type = "oneshot";
              serviceConfig.RemainAfterExit = true;

              script = with pkgs; "${iproute2}/bin/ip link set up lo";
            };

            deluge-natpmp = {
              description = "Configure a NAT-PMP port and configure Deluge with it.";
              after = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig.User = "deluge";
              serviceConfig.Group = "nogroup";

              script = with pkgs; ''
                #!/usr/bin/env bash
                set -euo pipefail

                # Deluge connection details
                DELUGE_DAEMON="${toString config.services.deluge.web.port}"

                OLD_PORT=""

                while true; do
                  # Ask Proton for a TCP mapping (internal port 1, external random, 60s lifetime)
                  out="$(${libnatpmp}/bin/natpmpc -a 1 0 tcp 60 -g 10.2.0.1 2>/dev/null || true)"

                  # Parse: "Mapped public port 53186 protocol TCP to local port 1 lifetime 60"
                  port="$(${gawk}/bin/awk '/Mapped public port/ {print $4; exit}' <<<"$out")"

                  if [[ -n "$port" && "$port" != "$OLD_PORT" ]]; then
                    echo "Got ProtonVPN forwarded port: $port – updating Deluge"

                    ${deluged}/bin/deluge-console \
                      "config --set random_port False ; \
                       config --set listen_ports ($port,$port)"

                    OLD_PORT="$port"
                  else
                    echo "Port unchanged, no-op"
                  fi

                  sleep 45
                done
              '';
            };
          };
        };
      })) config;
    };
  };
}
