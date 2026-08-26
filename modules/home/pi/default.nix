{ config, lib, pkgs, ... }:

let
  cfg = config.custom.home.pi;
  user = config.custom.user;
  piPackage = pkgs.unstable.pi-coding-agent;
  piSettings = {
    lastChangelogVersion = piPackage.version;
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    defaultThinkingLevel = "medium";
    enableInstallTelemetry = false;
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

      home.file.".pi/agent/settings.json" = {
        text = builtins.toJSON piSettings;
        force = true;
      };
    };
  };
}
