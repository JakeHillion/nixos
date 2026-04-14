{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.async_coder;
  fqdnParts = lib.splitString "." config.networking.fqdn;
  shortHost = "${builtins.elemAt fqdnParts 0}.${builtins.elemAt fqdnParts 1}";

  # Oh My OpenCode configuration for async-coder - all agents use Kimi K2.5
  ohMyOpencodeConfig = {
    agents = {
      sisyphus = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
      oracle = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
      librarian = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
      explore = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
      "multimodal-looker" = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
      prometheus = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
      metis = {
        model = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
      };
    };
    disabled_hooks = [ ];
    background_tasks = {
      max_concurrent = 5;
    };
  };
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

    # Deploy opencode and oh-my-opencode configs for the async-coder user
    systemd.tmpfiles.rules =
      let
        opencodeConfig = {
          plugin = [
            "file://${pkgs.opencode-with-plugins}/lib/opencode-plugins/opencode-plugin/dist/src/index.js"
            "file://${pkgs.opencode-with-plugins}/lib/opencode-plugins/oh-my-opencode/dist/index.js"
          ];
        };
      in
      [
        "d /var/lib/async-coder/.config/opencode 0755 async-coder async-coder -"
        "L+ /var/lib/async-coder/.config/opencode/opencode.json - - - - ${pkgs.writeText "opencode-async-coder.json" (builtins.toJSON opencodeConfig)}"
        "L+ /var/lib/async-coder/.config/opencode/oh-my-opencode.json - - - - ${pkgs.writeText "oh-my-opencode-async-coder.json" (builtins.toJSON ohMyOpencodeConfig)}"
      ];

    services.async-coder = {
      enable = true;
      opencode-package = pkgs.opencode-with-plugins;
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
              { owner = "JakeHillion"; name = "testquorum"; envrc = true; }
            ];
          };

          github = {
            type = "github";

            repositories = [
              { owner = "JakeHillion"; name = "hearthd"; envrc = true; }
              { owner = "JakeHillion"; name = "ogygia-nix"; envrc = true; }
              { owner = "testquorum"; name = "testquorum-rs"; envrc = true; }
            ];
          };
        };

        opencode = {
          api_key_file = config.age.secrets."async-coder/opencode-api-key".path;
          api_url = "https://api.fireworks.ai/inference/v1";
          model = "accounts/fireworks/routers/kimi-k2p5-turbo";
          cheap_fast_model = "accounts/fireworks/models/gpt-oss-20b";
          provider = "fireworks-ai";
          base_port = 18900;
        };
      };
    };
  };
}
