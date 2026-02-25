{ config, lib, ... }:

let
  cfg = config.custom.services.personal_agent;
  dataDir = "/var/lib/personal-agent";
in
{
  options.custom.services.personal_agent.enable = lib.mkEnableOption "personal-agent";

  config = lib.mkIf cfg.enable {
    custom.impermanence.extraDirs =
      lib.mkIf config.custom.impermanence.enable [ dataDir ];

    age.secrets = lib.genAttrs
      (map (s: "personal-agent/${s}") [
        "17track_token"
        "calendar_password"
        "fireworks_token"
        "matrix_password"
        "todoist_token"
      ])
      (name: {
        file = ./. + "/${lib.removePrefix "personal-agent/" name}.age";
        owner = "personal-agent";
        group = "personal-agent";
      });

    users.users.personal-agent.uid = config.ids.uids.personal-agent;
    users.groups.personal-agent.gid = config.ids.gids.personal-agent;

    services.personal-agent = {
      enable = true;
      settings = {
        state_dir = "${dataDir}/store";

        matrix = {
          homeserver_url = "https://matrix.hillion.co.uk";
          username = "personal-agent";
          display_name = "Higgins";
          avatar = ./higgins.png;
          password_file = config.age.secrets."personal-agent/matrix_password".path;
          device_display_name = "personal-agent";
          trusted_users = [ "@jake:hillion.co.uk" ];
        };
        llm = {
          default_model = "Kimi K2.5";
          providers = [{
            name = "fireworks";
            base_url = "https://api.fireworks.ai/inference/v1";
            token_file = config.age.secrets."personal-agent/fireworks_token".path;
            models = [{ id = "accounts/fireworks/models/kimi-k2p5"; name = "Kimi K2.5"; }];
          }];
        };

        calendar = {
          private = {
            server_url = "https://radicale.hillion.co.uk";
            username = "personal-agent";
            password_file = config.age.secrets."personal-agent/calendar_password".path;
            read_only = true;
            calendar_path = "/jake/69F72067-3C92-40C4-99FB-911D27FCD8E9";
          };
          travel = {
            server_url = "https://radicale.hillion.co.uk";
            username = "personal-agent";
            password_file = config.age.secrets."personal-agent/calendar_password".path;
            read_only = true;
            calendar_path = "/jake/94E7F50D-CDFC-41B6-BAC7-E94EBA42AF5D";
          };
        };
        seventeen_track = {
          token_file = config.age.secrets."personal-agent/17track_token".path;
          write = true;
        };
        todoist = { token_file = config.age.secrets."personal-agent/todoist_token".path; };
      };
    };
  };
}
