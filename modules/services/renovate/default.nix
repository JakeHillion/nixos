{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.renovate;

  configFile = pkgs.writeText "renovate-config.js" ''
    module.exports = {
        "endpoint": "https://gitea.hillion.co.uk/api/v1",
        "gitAuthor": "Renovate Bot <renovate-bot@noreply.gitea.hillion.co.uk>",
        "platform": "gitea",
        "onboardingConfigFileName": "renovate.json",
        "autodiscover": true,
        "optimizeForDisabled": true,
        "extends": [
          "config:recommended",
          "helpers:pinGitHubActionDigests"
        ]
    };
  '';
in
{
  options.custom.services.renovate = {
    enable = lib.mkEnableOption "renovate";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."renovate/environment" = {
      file = ./environment.age;
    };

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/cache/private/renovate" ];

    systemd.services.renovate = {
      description = "Renovate Bot - Automated dependency updates for Gitea repositories";

      path = with pkgs; [
        git
        nix
      ];

      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;

        CacheDirectory = "renovate";
        WorkingDirectory = "%C/renovate";

        EnvironmentFile = config.age.secrets."renovate/environment".path;
        ExecStart = "${pkgs.renovate}/bin/renovate";
      };

      environment = {
        HOME = "%C/renovate";
        RENOVATE_CONFIG_FILE = toString configFile;
        LOG_LEVEL = "debug";
      };
    };

    systemd.timers.renovate = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitInactiveSec = "45m";
      };
    };
  };
}
