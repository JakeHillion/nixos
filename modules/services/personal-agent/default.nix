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

    age.secrets."personal-agent/matrix_password" = {
      file = ./matrix_password.age;
      owner = "personal-agent";
      group = "personal-agent";
    };

    age.secrets."personal-agent/fireworks_token" = {
      file = ./fireworks_token.age;
      owner = "personal-agent";
      group = "personal-agent";
    };

    users.users.personal-agent.uid = config.ids.uids.personal-agent;
    users.groups.personal-agent.gid = config.ids.gids.personal-agent;

    services.personal-agent = {
      enable = true;
      settings = {
        matrix = {
          homeserver_url = "https://matrix.hillion.co.uk";
          username = "personal-agent";
          display_name = "Higgins";
          avatar = ./higgins.png;
          password_file = config.age.secrets."personal-agent/matrix_password".path;
          store_path = "${dataDir}/store";
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
      };
    };
  };
}
