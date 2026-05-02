{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.opencode;
  user = config.custom.user;

  kimi = "canopywave/moonshotai/kimi-k2.6";
  minimax = "canopywave/minimax/minimax-m2.5";
  glm = "ollama/glm-5.1";
  deepseek = "ollama/deepseek-v4-pro";

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
        "minimax/minimax-m2.5" = {
          name = "MiniMax M2.5 (CanopyWave)";
          limit = { context = 204800; output = 131072; };
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
        "deepseek-v4-pro" = {
          name = "DeepSeek V4 Pro (Ollama Pro)";
          limit = { context = 1000000; output = 384000; };
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
      # Communicators — GLM for strategic reasoning, K2.6 when quota exhausted
      sisyphus = { model = glm; fallback_models = [ kimi ]; };
      prometheus = { model = glm; fallback_models = [ kimi ]; };
      metis = { model = glm; fallback_models = [ kimi ]; };

      # Deep Specialists — DeepSeek V4 Pro with Think Max, K2.6 fallback
      # (GLM not in fallback: shares Ollama Pro quota with DeepSeek.)
      # DeepSeek V4 Pro's API takes reasoning_effort ∈ {"high","max"};
      # variant = "max" maps to the Think Max tier, "high" to Think High.
      oracle = { model = deepseek; variant = "max"; fallback_models = [ kimi ]; };
      momus = { model = deepseek; variant = "max"; fallback_models = [ kimi ]; };

      # K2.6 primary — active coordination and visual work
      atlas = { model = kimi; };
      multimodal-looker = { model = kimi; };

      # M2.5 primary — utility runners, speed over intelligence
      explore = { model = minimax; };
      librarian = { model = minimax; };
    };
    categories = {
      # DeepSeek V4 Pro Think Max, K2.6 fallback
      ultrabrain = { model = deepseek; variant = "max"; fallback_models = [ kimi ]; };

      # GLM for max reasoning, K2.6 fallback
      unspecified-high = { model = glm; fallback_models = [ kimi ]; };

      # DeepSeek V4 Pro Think High, K2.6 fallback
      # (DeepSeek's reasoning_effort space is just {"high","max"} — no medium.)
      deep = { model = deepseek; variant = "high"; fallback_models = [ kimi ]; };

      # K2.6 primary — execution categories where it leads
      visual-engineering = { model = kimi; };
      artistry = { model = kimi; };

      # M2.5 — fast, cheap utility tasks
      quick = { model = minimax; };

      # K2.6 — high volume, good enough
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
