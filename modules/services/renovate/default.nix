{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.renovate;

  # Git wrapper that adds change-id headers to commits using jj
  gitWrapper = pkgs.writeShellScriptBin "git" ''
    set -euo pipefail

    REAL_GIT="${pkgs.git}/bin/git"
    JJ="${pkgs.jujutsu}/bin/jj"

    # Always run the real git command first
    "$REAL_GIT" "$@"

    # Find the git subcommand (skip options that come before it)
    # e.g., "git -C /path commit -m msg" -> subcommand is "commit"
    subcommand=""
    skip_next=false
    for arg in "$@"; do
      if $skip_next; then
        skip_next=false
        continue
      fi
      case "$arg" in
        # Options that take a value (next arg is the value)
        -C|-c|--git-dir|--work-tree|--namespace|--config-env)
          skip_next=true
          ;;
        # Options that don't take a value
        -*)
          ;;
        # First non-option is the subcommand
        *)
          subcommand="$arg"
          break
          ;;
      esac
    done

    # Only add change-id for commit commands
    [[ "$subcommand" == "commit" ]] || exit 0

    # Initialize jj colocation if needed
    if [ ! -d .jj ]; then
      "$JJ" git init
    fi

    # Generate and export change-id to the new commit
    "$JJ" metaedit --update-change-id @-
  '';

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
        config.nix.package
        gitWrapper

        cargo
        nodejs
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
        # jj requires user identity
        JJ_USER = "Renovate Bot";
        JJ_EMAIL = "renovate-bot@noreply.gitea.hillion.co.uk";
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
