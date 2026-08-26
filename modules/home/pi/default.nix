{ config, lib, pkgs, ... }:

let
  cfg = config.custom.home.pi;
  user = config.custom.user;
  piPackage = pkgs.unstable.pi-coding-agent;
  piWebAccess = pkgs.piPackages.pi-web-access;
  piExtensions = pkgs.linkFarm "pi-extensions" [
    {
      name = "subagent";
      path = "${piPackage}/lib/node_modules/pi-monorepo/examples/extensions/subagent";
    }
    {
      name = "pi-web-access";
      path = "${piWebAccess}/lib/node_modules/pi-web-access";
    }
  ];
  # ~/.pi/web-search.json for the pi-web-access extension. The Kagi API key is
  # not stored here nor injected into any shell: pi-web-access resolves it lazily
  # from the decrypted agenix secret via its "!command" credential source (an
  # absolute-path `cat` of the agenix secret), so the key exists only inside the
  # agenix-encrypted secret.
  piWebSearch = {
    provider = "kagi";
    kagiApiKey = "!${pkgs.coreutils}/bin/cat ${config.age.secrets."pi/kagi-api-key".path}";
    fetchRouting = {
      providers = [ "kagi" ];
      allowRemoteHostedProviders = true;
    };
    webSearch.enabled = true;
    tools = {
      webSearch = { enabled = true; };
      fetchContent = { enabled = true; };
      sourceCheck = { enabled = false; };
      getSearchContent = { enabled = false; };
    };
    commands = {
      websearch = { enabled = false; };
      curator = { enabled = false; };
      search = { enabled = false; };
      "google-account" = { enabled = false; };
    };
    # Features outside our Kagi search + HTML/kagi fetch scope.
    githubClone = { enabled = false; };
    githubPrIssue = { enabled = false; };
    youtube = { enabled = false; };
    video = { enabled = false; };
    pdf = { enabled = false; };
  };
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

    # Kagi API key for pi-web-access. Master-encrypted source under
    # secrets/pi/; rekey to each host that enables this module (`agenix rekey
    # -f`), then rebuild.
    age.secrets."pi/kagi-api-key" = {
      rekeyFile = ../../../secrets/pi/kagi-api-key.age;
      owner = user;
      mode = "0400";
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
        ".pi/web-search.json" = {
          text = builtins.toJSON piWebSearch;
          force = true;
        };
      };
    };
  };
}
