{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.opencode;
  user = config.custom.user;

  # Plugin paths from the bundled package
  pluginPaths = pkgs.opencode-with-plugins;

  opencodeConfig = {
    plugin = [
      "file://${pluginPaths}/lib/opencode-plugins/opencode-plugin/dist/src/index.js"
      "file://${pluginPaths}/lib/opencode-plugins/oh-my-opencode/dist/index.js"
    ];
  };

  # Oh My OpenCode configuration with all agents using Kimi K2.5 via Fireworks AI
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
    # Enable all features by default
    disabled_hooks = [ ];
    # Background task configuration
    background_tasks = {
      max_concurrent = 5;
    };
  };
in
{
  options.custom.home.opencode.enable = lib.mkEnableOption "OpenCode setup";

  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      home.packages = [ pkgs.opencode-with-plugins ];

      # Deploy OpenCode config with plugin references
      xdg.configFile."opencode/opencode.json".text = builtins.toJSON opencodeConfig;

      # Deploy Oh My OpenCode configuration
      xdg.configFile."opencode/oh-my-opencode.json".text = builtins.toJSON ohMyOpencodeConfig;
    };

    custom.impermanence = lib.mkIf config.custom.impermanence.enable {
      userExtraDirs.${user} = [ ".local/share/opencode" ];
    };
  };
}
