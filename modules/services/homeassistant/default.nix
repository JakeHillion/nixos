{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.homeassistant;

  acmeApiHost =
    let
      authDns = config.custom.locations.locations.services.authoritative_dns;
    in
    if builtins.isList authDns then builtins.head authDns else authDns;

  # Override the nixpkgs ecoflow_cloud (pinned to v1.4.1) with the latest
  # tagged release, which adds Wave 3 support. Drop this once nixpkgs ships a
  # release >= 1.5.0.
  ecoflow_cloud = pkgs.home-assistant-custom-components.ecoflow_cloud.overrideAttrs (old: rec {
    version = "1.5.0-beta3";
    src = pkgs.fetchFromGitHub {
      owner = "tolwi";
      repo = "hassio-ecoflow-cloud";
      tag = "v${version}";
      hash = "sha256-qG/z2MHZDd5S7KWwvRViWJqEFIGBS2hNWi3w71rXB+o=";
    };
  });
in
{
  options.custom.services.homeassistant = {
    enable = lib.mkEnableOption "homeassistant";

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
    };
  };

  config = lib.mkIf cfg.enable {
    services.home-assistant.configDir = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "/data/home-assistant");

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/matter-server" ];

    age.secrets = {
      "backups/homeassistant/restic/mig29" = lib.mkIf cfg.backup {
        rekeyFile = ../../../secrets/restic/mig29.age;
        owner = "hass";
        group = "hass";
      };
      "backups/homeassistant/restic/b52" = lib.mkIf cfg.backup {
        rekeyFile = ../../../secrets/restic/b52.age;
        owner = "postgres";
        group = "postgres";
      };

      "homeassistant/secrets.yaml" = {
        file = ../../../secrets/homeassistant/secrets.yaml.age;
        path = "${config.services.home-assistant.configDir}/secrets.yaml";
        owner = "hass";
        group = "hass";
      };

      "homeassistant/pdu_password" = {
        file = ./pdu_password.age;
        owner = "hass";
        group = "hass";
      };
    };

    services = {
      postgresqlBackup = lib.mkIf cfg.backup {
        enable = true;
        compression = "none"; # for better diffing
        databases = [ "homeassistant" ];
      };

      restic.backups = lib.mkIf cfg.backup {
        "homeassistant-config" = {
          user = "hass";
          timerConfig = {
            OnCalendar = "03:00";
            RandomizedDelaySec = "60m";
          };
          repository = "rest:https://restic.${config.ogygia.domain}/mig29";
          passwordFile = config.age.secrets."backups/homeassistant/restic/mig29".path;
          paths = [
            config.services.home-assistant.configDir
          ];
        };
        "homeassistant-database" = {
          user = "postgres";
          timerConfig = {
            OnCalendar = "03:00";
            RandomizedDelaySec = "60m";
          };
          repository = "rest:https://restic.${config.ogygia.domain}/b52";
          passwordFile = config.age.secrets."backups/homeassistant/restic/b52".path;
          paths = [
            "${config.services.postgresqlBackup.location}/homeassistant.sql"
          ];
        };
      };

      caddy = {
        enable = true;

        virtualHosts = {
          "homeassistant.iot.home.jakehillion.me" = {
            listenAddresses = [ "10.239.19.8" ];
            extraConfig = ''
              tls {
                dns jakehillion {
                  api_endpoint http://${acmeApiHost}:8553
                }
              }

              @blocked not remote_ip 10.239.19.4 10.239.19.14
              respond @blocked "<h1>Access Denied</h1>" 403

              reverse_proxy http://localhost:8123
            '';
          };
        };
      };

      postgresql = {
        enable = true;
        initialScript = pkgs.writeText "homeassistant-init.sql" ''
          CREATE ROLE "hass" WITH LOGIN;
          CREATE DATABASE "homeassistant" WITH OWNER "hass" ENCODING "utf8";
        '';
      };

      wyoming = {
        piper.servers.default = {
          enable = true;
          uri = "tcp://0.0.0.0:10200";

          voice = "en_GB-southern_english_female-low";
        };

        faster-whisper.servers.default = {
          enable = true;
          uri = "tcp://0.0.0.0:10300";

          language = "en";
        };
      };

      matter-server = {
        enable = true;
        logLevel = "debug";
        extraArgs = {
          # Only the local Home Assistant talks to this.
          listen-address = "127.0.0.1";
          # OTBR publishes Thread devices via avahi on iot; without this,
          # CHIP picks eth0 and never resolves the OMR-prefix AAAAs.
          primary-interface = "iot";
        };
      };

      home-assistant = {
        enable = true;

        extraPackages = python3Packages: with python3Packages; [
          psycopg2 # postgresql support
        ];
        extraComponents = [
          "bluetooth"
          "default_config"
          "esphome"
          "fully_kiosk"
          "google_assistant"
          "homekit"
          "matter"
          "met"
          "mobile_app"
          "mqtt"
          "otbr"
          "otp"
          "smartthings"
          "sonos"
          "sun"
          "thread"
          "unifi"
          "wake_on_lan"
          "waze_travel_time"
          "wyoming"
        ];
        customComponents = [
          ecoflow_cloud
        ]
        ++ (with pkgs.home-assistant-custom-components; [
          adaptive_lighting
          octopus_energy
        ]);
        customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
          button-card
        ];

        config = lib.mkMerge [
          {
            default_config = { };

            logger = {
              default = "info";
              logs = {
                "homeassistant.components.matter" = "debug";
                "matter_server" = "debug";
                "chip" = "debug";
              };
            };

            homeassistant = {
              internal_url = "https://homeassistant.iot.home.jakehillion.me";

              auth_providers = [
                { type = "homeassistant"; }
                {
                  type = "trusted_networks";
                  trusted_networks = [ "10.239.19.4/32" ];
                  trusted_users = {
                    "10.239.19.4" = "fb4979873ecb480d9e3bb336250fa344";
                  };
                  allow_bypass_login = true;
                }
              ];
            };

            recorder = {
              db_url = "postgresql://@/homeassistant";
            };

            http = {
              use_x_forwarded_for = true;
              trusted_proxies = with config.custom.dns.authoritative; [
                "::1"
                ipv4.me.jakehillion.neb.cx.boron
              ];
            };

            google_assistant = {
              project_id = "homeassistant-8de41";
              service_account = {
                client_email = "!secret google_assistant_service_account_client_email";
                private_key = "!secret google_assistant_service_account_private_key";
              };
              report_state = true;
              expose_by_default = true;
              exposed_domains = [ "light" ];
              entity_config = {
                "input_boolean.sleep_mode" = { };
              };
            };
            homekit = [{
              filter = {
                include_domains = [ "light" ];
              };
            }];

            bluetooth = { };

            adaptive_lighting =
              let
                common = {
                  min_sunset_time = "21:00";
                };
              in
              [
                ({
                  name = "main lights";
                  lights = [
                    "light.bedroom_lamp"
                    "light.bedroom_light"
                    "light.cubby_light"
                    "light.desk_lamp"
                    "light.hallway_light"
                    "light.living_room_lamp"
                    "light.living_room_light"
                    "light.wardrobe_light"
                  ];
                } // common)
                ({
                  # separate to more vigorously disable and allow the fancy settings
                  name = "hue";
                  lights = [
                    "light.living_room_hue_lamp"
                  ];
                  detect_non_ha_changes = true;
                } // common)
              ];

            sensor = [
              {
                # Time/Date (for automations)
                platform = "time_date";
                display_options = [
                  "date"
                  "date_time_iso"
                ];
              }

              {
                # Living Room Temperature
                platform = "statistics";
                name = "Living Room temperature (rolling average)";
                entity_id = "sensor.living_room_environment_sensor_temperature";
                state_characteristic = "average_linear";
                unique_id = "e86198a8-88f4-4822-95cb-3ec7b2662395";
                max_age = {
                  minutes = 5;
                };
              }
            ];

            input_boolean = {
              sleep_mode = {
                name = "Set house to sleep mode";
                icon = "mdi:sleep";
              };
            };


            # UI managed expansions
            automation = "!include automations.yaml";
            script = "!include scripts.yaml";
            scene = "!include scenes.yaml";
          }

          (import ./servers.nix { inherit config pkgs lib; })
        ];
      };
    };
  };
}
