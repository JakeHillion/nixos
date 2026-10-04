{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.renovate;

  gitAuthorName = "Renovate Bot";
  gitAuthorEmail = "renovate-bot@noreply.gitea.hillion.co.uk";

  # Git wrapper that adds change-id headers to commits using jj
  gitWrapper = pkgs.writeShellScriptBin "git" ''
    set -euo pipefail

    REAL_GIT="${pkgs.git}/bin/git"

    # Renovate spawns git with a filtered environment, so jj takes its identity
    # on the command line instead of from JJ_USER/JJ_EMAIL.
    jj() {
      "${pkgs.jujutsu}/bin/jj" --config "user.name=${gitAuthorName}" --config "user.email=${gitAuthorEmail}" "$@"
    }

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
      jj git init
    fi

    # Generate and export change-id to the new commit
    jj metaedit --update-change-id @-
  '';

  configFile = pkgs.writeText "renovate-config.js" ''
    module.exports = {
        "endpoint": "https://gitea.hillion.co.uk/api/v1",
        "gitAuthor": "${gitAuthorName} <${gitAuthorEmail}>",
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
    age.secrets."renovate/environment".rekeyFile = ./environment.age;

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/cache/private/renovate" ];

    systemd.services.renovate = {
      description = "Renovate Bot - Automated dependency updates for Gitea repositories";

      path = with pkgs; [
        config.nix.package
        gitWrapper

        cargo
        go
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
