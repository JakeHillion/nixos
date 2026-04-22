{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.opencode;
  user = config.custom.user;

  kimi = "canopywave/moonshotai/kimi-k2.6";
  glm = "ollama/glm-5.1";

  opencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    model = kimi;
    small_model = kimi;
    provider.canopywave = {
      npm = "@ai-sdk/openai-compatible";
      name = "CanopyWave";
      options = {
        baseURL = "https://inference.canopywave.io/v1";
        apiKey = "{file:${config.age.secrets."opencode/canopywave-api-key".path}}";
      };
      models = {
        "moonshotai/kimi-k2.6" = {
          name = "Kimi K2.6 (CanopyWave)";
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
    disabled_agents = [ "hephaestus" ];
    agents = {
      # GLM for strategic reasoning, K2.6 when quota exhausted
      sisyphus = { model = glm; fallback_models = [ kimi ]; };
      prometheus = { model = glm; fallback_models = [ kimi ]; };
      metis = { model = glm; fallback_models = [ kimi ]; };
      oracle = { model = glm; fallback_models = [ kimi ]; };
      momus = { model = glm; fallback_models = [ kimi ]; };

      # K2.6 primary — active coordination and visual work
      atlas = { model = kimi; };
      multimodal-looker = { model = kimi; };

      # K2.5 free — pure utility, volume absorption
      explore = { model = kimi; };
      librarian = { model = kimi; };
    };
    categories = {
      # GLM for max reasoning, K2.6 fallback
      ultrabrain = { model = glm; fallback_models = [ kimi ]; };
      unspecified-high = { model = glm; fallback_models = [ kimi ]; };

      # K2.6 primary — execution categories where it leads
      deep = { model = kimi; };
      visual-engineering = { model = kimi; };
      artistry = { model = kimi; };

      # K2.5 free — high volume, good enough
      quick = { model = kimi; };
      unspecified-low = { model = kimi; };
      writing = { model = kimi; };
    };
  };
in
{
  options.custom.home.opencode.enable = lib.mkEnableOption "OpenCode setup";

  config = lib.mkIf cfg.enable {
    age.secrets."opencode/canopywave-api-key" = {
      rekeyFile = ../../secrets/ai/canopy-wave-unlimited.age;
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
