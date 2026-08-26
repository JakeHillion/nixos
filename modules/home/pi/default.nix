{ config, lib, pkgs, ... }:

let
  cfg = config.custom.home.pi;
  user = config.custom.user;
  piPackage = pkgs.unstable.pi-coding-agent;
  piExtensions = pkgs.linkFarm "pi-extensions" [
    {
      name = "subagent";
      path = "${piPackage}/lib/node_modules/pi-monorepo/examples/extensions/subagent";
    }
  ];
  piSettings = {
    lastChangelogVersion = piPackage.version;
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    defaultThinkingLevel = "medium";
    enableInstallTelemetry = false;
  };
  piModels.providers.llm-proxy = {
    baseUrl = "http://127.0.0.1:9100/v1/batch/30000";
    api = "openai-completions";
    apiKey = "unused";
    models = [{
      id = "deepseek/deepseek-v4-flash-0731";
      contextWindow = 1000000;
    }];
  };
in
{
  options.custom.home.pi.enable = lib.mkEnableOption "Pi coding agent setup";

  config = lib.mkIf cfg.enable {
    custom.impermanence = lib.mkIf config.custom.impermanence.enable {
      userExtraFiles.${user} = [
        ".pi/agent/auth.json"
        ".pi/agent/trust.json"
      ];
      userExtraDirs.${user} = [ ".pi/agent/sessions" ];
    };

    home-manager.users.${user} = {
      home = {
        packages = [ piPackage ];
        sessionVariables = {
          PI_SKIP_VERSION_CHECK = "1";
          PI_TELEMETRY = "0";
        };
      };

      home.file = {
        ".pi/agent/settings.json" = {
          text = builtins.toJSON piSettings;
          force = true;
        };
        ".pi/agent/models.json" = {
          text = builtins.toJSON piModels;
          force = true;
        };
        ".pi/agent/agents" = {
          source = ./agents;
          force = true;
        };
        ".pi/agent/extensions" = {
          source = piExtensions;
          force = true;
        };
      };
    };
  };
}
