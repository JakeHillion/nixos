{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.async_coder;
  fqdnParts = lib.splitString "." config.networking.fqdn;
  shortHost = "${builtins.elemAt fqdnParts 0}.${builtins.elemAt fqdnParts 1}";
in
{
  options.custom.services.async_coder = {
    enable = lib.mkEnableOption "async-coder";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."async-coder/${shortHost}.password" = {
      file = ./${shortHost}.password.age;
      owner = "async-coder";
      group = "async-coder";
    };
    age.secrets."async-coder/opencode-api-key" = {
      file = ./opencode-api-key.age;
      owner = "async-coder";
      group = "async-coder";
    };

    users.users.async-coder.uid = config.ids.uids.async-coder;
    users.groups.async-coder.gid = config.ids.gids.async-coder;

    services.async-coder = {
      enable = true;
      opencode-package = pkgs.unstable.opencode;
      settings = {
        homeserver_url = "https://matrix.hillion.co.uk";
        username = shortHost;
        password_file = config.age.secrets."async-coder/${shortHost}.password".path;

        avatar = ./${shortHost}.png;
        store_path = "/var/lib/async-coder/store";
        device_display_name = "async-coder";
        trusted_users = [ "@jake:hillion.co.uk" ];
        root_space = "!WhggIMMfLMutJEDsdv:hillion.co.uk";

        git_author_name = "Jake Hillion";
        git_author_email = "jake@hillion.co.uk";

        forges.gitea = {
          type = "gitea";
          url = "https://gitea.hillion.co.uk";
          ssh_url = "git@ssh.gitea.hillion.co.uk";

          repositories = [
            { owner = "JakeHillion"; name = "async-coder"; }
          ];
        };

        opencode = {
          api_key_file = config.age.secrets."async-coder/opencode-api-key".path;
          api_url = "https://api.fireworks.ai/inference/v1";
          model = "accounts/fireworks/models/kimi-k2p5";
          provider = "fireworks";
          base_port = 18900;
        };
      };
    };
  };
}
