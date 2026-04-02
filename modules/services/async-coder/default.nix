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
    age.secrets = lib.genAttrs
      (map (s: "async-coder/${s}") [
        "${shortHost}.password"
        "gitea-token"
        "opencode-api-key"
      ])
      (name: {
        file = ./. + "/${lib.removePrefix "async-coder/" name}.age";
        owner = "async-coder";
        group = "async-coder";
      });

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

        forges = {
          gitea = {
            type = "gitea";
            url = "https://gitea.hillion.co.uk";
            ssh_url = "git@ssh.gitea.hillion.co.uk";
            token_file = config.age.secrets."async-coder/gitea-token".path;

            repositories = [
              { owner = "JakeHillion"; name = "async-coder"; envrc = true; }
              { owner = "JakeHillion"; name = "nixos"; jujutsu_mode = true; }
              { owner = "JakeHillion"; name = "personal-agent"; envrc = true; }
              { owner = "JakeHillion"; name = "testquorum"; }
            ];
          };

          github = {
            type = "github";

            repositories = [
              { owner = "exo-explore"; name = "exo"; feature_prefix = "JakeHillion/"; }
              { owner = "exo-explore"; name = "exo-internal"; feature_prefix = "JakeHillion/"; }
            ];
          };
        };

        opencode = {
          api_key_file = config.age.secrets."async-coder/opencode-api-key".path;
          api_url = "https://api.fireworks.ai/inference/v1";
          model = "accounts/fireworks/routers/kimi-k2p5-turbo";
          cheap_fast_model = "accounts/fireworks/models/glm-4p7"; # TODO: this isn't cheap or fast, but the small fast ones don't seem to work
          provider = "fireworks-ai";
          base_port = 18900;
        };
      };
    };
  };
}
