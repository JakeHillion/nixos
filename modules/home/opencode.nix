{ config, lib, ... }:

let
  cfg = config.custom.home.opencode;
  systemCfg = config;

  # Helper to get ollama providers from a host's configuration
  # We need to access the global locations to discover ollama hosts
  ollamaHosts = 
    let
      ollamaServices = systemCfg.custom.locations.locations.services.ollama;
    in
      if builtins.isList ollamaServices
      then ollamaServices
      else [ ollamaServices ];

  # Build provider configurations from discovered ollama hosts
  # This is a placeholder - in practice, we'd need inter-host communication
  # For now, we'll just use the configuration from the host-specific settings
  globalProviders = cfg.providers;

  # Add local provider if requested and ollama is enabled locally
  localProvider = lib.attrsets.optionalAttrs 
    (cfg.includeLocalProvider && systemCfg.custom.services.ollama.enable)
    (lib.attrsets.mapAttrs 
      (name: value: value // { 
        baseURL = lib.strings.replaceStrings 
          [ "http://ollama.${systemCfg.ogygia.domain}" ] 
          [ "http://localhost" ] 
          value.baseURL; 
      })
      systemCfg.custom.services.ollama.providers);

  allProviders = globalProviders // localProvider;

  # Convert provider configuration to OpenCode format
  openCodeProviders = lib.attrsets.mapAttrs
    (providerName: providerConfig: {
      npm = "@ai-sdk/openai-compatible";
      name = providerConfig.name;
      options.baseURL = providerConfig.baseURL;
      models = lib.attrsets.mapAttrs
        (modelName: modelConfig: {
          name = modelConfig.displayName;
        })
        providerConfig.models;
    })
    allProviders;

  openCodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    model = cfg.defaultModel;
    provider = openCodeProviders;
  };
in
{
  options.custom.home.opencode = {
    enable = lib.mkEnableOption "opencode";

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "ollama/ollama_chat/qwen2.5-coder:14b";
      description = "Default model to use in OpenCode";
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name for the provider";
          };

          baseURL = lib.mkOption {
            type = lib.types.str;
            description = "Base URL for the Ollama API";
          };

          models = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                id = lib.mkOption {
                  type = lib.types.str;
                  description = "Model ID for OpenCode (e.g., ollama_chat/qwen2.5-coder:14b)";
                };
                displayName = lib.mkOption {
                  type = lib.types.str;
                  description = "Human-readable model name";
                };
              };
            });
            default = {};
            description = "Models available from this provider";
          };
        };
      });
      default = {};
      description = "Ollama providers to configure for OpenCode";
    };

    includeLocalProvider = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include local ollama instance if available";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${systemCfg.custom.user} = {
      home.file.".config/opencode/opencode.json" = {
        text = builtins.toJSON openCodeConfig;
      };
    };

    custom.impermanence = lib.mkIf systemCfg.custom.impermanence.enable {
      userExtraDirs.${systemCfg.custom.user} = [ ".local/share/opencode" ];
    };
  };
}
