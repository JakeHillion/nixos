{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.homeassistant;
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
    custom = {
      backups.homeassistant.enable = cfg.backup;
    };

    age.secrets."homeassistant/secrets.yaml" = {
      file = ../../secrets/homeassistant/secrets.yaml.age;
      path = "${config.services.home-assistant.configDir}/secrets.yaml";
      owner = "hass";
      group = "hass";
    };

    services = {
      postgresql = {
        enable = true;
        initialScript = pkgs.writeText "homeassistant-init.sql" ''
          CREATE ROLE "hass" WITH LOGIN;
          CREATE DATABASE "homeassistant" WITH OWNER "hass" ENCODING "utf8";
        '';
      };

      home-assistant = {
        enable = true;

        extraPackages = python3Packages: with python3Packages; [
          psycopg2 # postgresql support
        ];
        extraComponents = [
          "bluetooth"
          "default_config"
          "esphome"
          "fully_kiosk"
          "google_assistant"
          "homekit"
          "met"
          "mobile_app"
          "mqtt"
          "otp"
          "smartthings"
          "sonos"
          "sun"
          "wake_on_lan"
          "waze_travel_time"
        ];
        customComponents = with pkgs.home-assistant-custom-components; [
          adaptive_lighting
        ];

        config = {
          default_config = { };

          homeassistant = {
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
              ipv4.uk.co.hillion.ts.cx.boron
              ipv6.uk.co.hillion.ts.cx.boron
              ipv4.uk.co.hillion.ts.pop.sodium
              ipv6.uk.co.hillion.ts.pop.sodium
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

          adaptive_lighting = {
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
            min_sunset_time = "21:00";
          };

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

          switch = [
            {
              name = "merlin.rig.ts.hillion.co.uk";
              platform = "wake_on_lan";
              mac = "b0:41:6f:13:20:14";
              host = "10.64.50.28";
            }
          ];

          # UI managed expansions
          automation = "!include automations.yaml";
          script = "!include scripts.yaml";
          scene = "!include scenes.yaml";
        };
      };
    };
  };
}
