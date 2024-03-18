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
          "flux"
          "google_assistant"
          "homekit"
          "met"
          "mobile_app"
          "mqtt"
          "otp"
          "sun"
          "switchbot"
        ];

        config = {
          default_config = { };

          recorder = {
            db_url = "postgresql://@/homeassistant";
          };

          http = {
            use_x_forwarded_for = true;
            trusted_proxies = [ "100.96.143.138" ];
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
          };
          homekit = [{
            filter = {
              include_domains = [ "light" ];
            };
          }];

          bluetooth = { };

          switch = [
            {
              platform = "flux";
              start_time = "07:00";
              stop_time = "23:59";
              mode = "mired";
              disable_brightness_adjust = true;
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
            }
          ];

          light = [
            {
              platform = "template";
              lights = {
                bathroom_light = {
                  unique_id = "87a4cbb5-e5a7-44fd-9f28-fec2d6a62538";
                  value_template = "on";
                  turn_on = { service = "script.noop"; };
                  turn_off = {
                    service = "switch.turn_on";
                    entity_id = "switch.bathroom_light";
                  };
                };
              };
            }
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

          # UI managed expansions
          automation = "!include automations.yaml";
          script = "!include scripts.yaml";
          scene = "!include scenes.yaml";
        };
      };
    };
  };
}
