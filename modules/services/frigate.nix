{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.frigate;
in
{
  options.custom.services.frigate = {
    enable = lib.mkEnableOption "frigate";

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/frigate";
    };
    recordingsPath = lib.mkOption {
      type = lib.types.str;
      default = "/practical-defiant-coffee/cctv";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."frigate/secrets.env".file = ../../secrets/frigate/secrets.env.age;

    services.caddy = {
      enable = true;

      virtualHosts."frigate.neb.jakehillion.me" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          reverse_proxy unix///run/nginx-frigate/nginx.sock

          tls {
            ca https://ca.ts.hillion.co.uk:8443/acme/acme/directory
          }
        '';
      };
    };

    users.users.frigate = {
      group = "frigate";
      home = cfg.dataPath;
      createHome = true;
      uid = config.ids.uids.frigate;
    };
    users.groups.frigate.gid = config.ids.gids.frigate;

    users.users.nginx = {
      group = "nginx";
      uid = config.ids.uids.nginx;
    };
    users.groups.nginx.gid = config.ids.gids.nginx;

    systemd.tmpfiles.rules = [
      "d /run/nginx-frigate 0750 nginx caddy - -"
    ];

    containers."frigate" = {
      autoStart = true;
      ephemeral = true;
      additionalCapabilities = [ "CAP_NET_ADMIN" ];

      macvlans = [ "cameras" ];
      bindMounts = {
        "/run/agenix/frigate/secrets.env".hostPath = config.age.secrets."frigate/secrets.env".path;
        "/run/nginx-frigate" = { hostPath = "/run/nginx-frigate"; isReadOnly = false; };

        "/var/lib/frigate" = { hostPath = cfg.dataPath; isReadOnly = false; };
        "/var/lib/frigate/recordings" = { hostPath = cfg.recordingsPath; isReadOnly = false; };
      };

      config = (hostConfig: { config, pkgs, ... }: {
        config = {
          system.stateVersion = "24.05";

          systemd.network = {
            enable = true;
            networks."10-cameras" = {
              matchConfig.Name = "mv-cameras";
              networkConfig.DHCP = "ipv4";
              dhcpV4Config.ClientIdentifier = "mac";
              linkConfig.MACAddress = "00:b7:43:f3:81:a0";
            };
          };
          services.resolved.enable = false;

          users.users.frigate.uid = hostConfig.ids.uids.frigate;
          users.groups.frigate.gid = hostConfig.ids.gids.frigate;

          users.users.nginx.extraGroups = [ "frigate" ];
          services.nginx.virtualHosts."frigate.ts.hillion.co.uk".listen = lib.mkForce [
            { addr = "unix:/run/nginx-frigate/nginx.sock"; }
          ];

          services.frigate = {
            enable = true;
            package = pkgs.frigate;
            hostname = "frigate.ts.hillion.co.uk";

            settings = {
              record = {
                enabled = true;
                retain.mode = "motion";
              };

              cameras = {
                living_room = {
                  enabled = true;
                  ffmpeg.inputs = [
                    {
                      path = "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@10.133.145.2:554/h264Preview_01_sub";
                      roles = [ "detect" ];
                    }
                    {
                      path = "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@10.133.145.2:554/h264Preview_01_main";
                      roles = [ "record" ];
                    }
                  ];
                };
              };
            };
          };
          systemd.services.frigate.serviceConfig.EnvironmentFile = "/run/agenix/frigate/secrets.env";
        };
      }) config;
    };

  };
}
