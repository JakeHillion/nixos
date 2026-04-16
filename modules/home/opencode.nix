{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.opencode;
  user = config.custom.user;

  kimi = "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo";
  glm = "ollama/glm-5.1";

  opencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    model = kimi;
    small_model = kimi;
    provider.fireworks-ai = {
      npm = "@ai-sdk/openai-compatible";
      name = "Fireworks AI";
      options = {
        baseURL = "https://api.fireworks.ai/inference/v1";
        apiKey = "{file:${config.age.secrets."opencode/fireworks-api-key".path}}";
      };
      models = {
        "accounts/fireworks/routers/kimi-k2p5-turbo" = {
          name = "Kimi K2.5 Turbo (Firepass)";
          limit = { context = 256000; output = 65536; };
        };
      };
    };
    provider.ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama Cloud";
      options = {
        baseURL = "https://ollama.com/v1";
        apiKey = "{file:${config.age.secrets."opencode/ollama-api-key".path}}";
      };
      models = {
        "glm-5.1" = {
          name = "GLM-5.1 (Ollama Pro)";
          limit = { context = 202752; output = 65536; };
        };
      };
    };
    plugin = [
      "file://${pkgs.opencode-plugin}/lib/opencode-plugin/dist/src/index.js"
      "file://${pkgs.oh-my-openagent}/lib/oh-my-openagent/dist/index.js"
    ];
  };

  omoConfig = {
    "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
    agents = {
      sisyphus = { model = glm; fallback_models = [ kimi ]; };
      hephaestus = { model = glm; allow_non_gpt_model = true; fallback_models = [ kimi ]; };
      prometheus = { model = glm; fallback_models = [ kimi ]; };
      metis = { model = glm; fallback_models = [ kimi ]; };
      atlas = { model = kimi; };
      explore = { model = kimi; };
      librarian = { model = kimi; };
      multimodal-looker = { model = kimi; };
      oracle = { model = glm; fallback_models = [ kimi ]; };
      momus = { model = glm; fallback_models = [ kimi ]; };
    };
    categories = {
      quick = { model = kimi; };
      unspecified-low = { model = kimi; };
      unspecified-high = { model = glm; fallback_models = [ kimi ]; };
      writing = { model = kimi; };
      visual-engineering = { model = kimi; };
      ultrabrain = { model = glm; fallback_models = [ kimi ]; };
      deep = { model = glm; fallback_models = [ kimi ]; };
      artistry = { model = glm; fallback_models = [ kimi ]; };
    };
  };
in
{
  options.custom.home.opencode.enable = lib.mkEnableOption "OpenCode setup";

  config = lib.mkIf cfg.enable {
    age.secrets."opencode/fireworks-api-key" = {
      rekeyFile = ./opencode-fireworks-api-key.age;
      owner = user;
      group = "users";
    };

    age.secrets."opencode/ollama-api-key" = {
      rekeyFile = ./opencode-ollama-api-key.age;
      owner = user;
      group = "users";
    };

    home-manager.users.${user} = {
      home.packages = [ pkgs.unstable.opencode ];

      home.sessionVariables.OMO_SEND_ANONYMOUS_TELEMETRY = "0";

      xdg.configFile."opencode/opencode.json".text = builtins.toJSON opencodeConfig;
      xdg.configFile."opencode/oh-my-openagent.json".text = builtins.toJSON omoConfig;
    };

    custom.impermanence = lib.mkIf config.custom.impermanence.enable {
      userExtraDirs.${user} = [ ".local/share/opencode" ];
    };
  };
}
