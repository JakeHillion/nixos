{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.renovate;

  giteaUrl = "https://gitea.hillion.co.uk";
  gitAuthorName = "Renovate Bot";
  gitAuthorEmail = "renovate-bot@noreply.gitea.hillion.co.uk";

  # curl leaves credentials out of the effective URL, which git takes for a
  # redirect to a URL without Renovate's token, so git needs another way to get
  # it for the requests that follow.
  credentialHelper = pkgs.writeShellScript "renovate-git-credential" ''
    set -euo pipefail
    [[ "$1" == "get" ]] || exit 0
    . /run/credentials/renovate.service/environment
    printf 'username=%s\npassword=x-oauth-basic\n' "$RENOVATE_TOKEN"
  '';

  # Git wrapper that adds change-id headers to commits using jj
  gitWrapper = pkgs.writeShellScriptBin "git" ''
    set -euo pipefail

    REAL_GIT="${pkgs.git}/bin/git"

    # Renovate spawns git with a filtered environment, so jj takes its identity
    # on the command line instead of from JJ_USER/JJ_EMAIL.
    jj() {
      "${pkgs.unstable.jujutsu}/bin/jj" --config "user.name=${gitAuthorName}" --config "user.email=${gitAuthorEmail}" "$@"
    }

    # Always run the real git command first
    "$REAL_GIT" -c "credential.${giteaUrl}.helper=${credentialHelper}" "$@"

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

  # Repositories run this as a post-upgrade task, so it takes nothing from them
  # but Go module directories: it reads their Go files and never evaluates or
  # builds the repository's Nix. It hashes the vendor directory the way
  # buildGoModule does, into pkgs/vendor-hashes.json keyed by directory.
  updateVendorHash = pkgs.writeShellApplication {
    name = "renovate-update-vendor-hash";
    runtimeInputs = with pkgs; [ coreutils go jq config.nix.package ];
    text = ''
      usage() {
        echo "usage: renovate-update-vendor-hash go <module directory>..." >&2
        exit 1
      }
      [ "''${1-}" = go ] || usage
      shift
      [ $# -gt 0 ] || usage

      root=$(pwd -P)
      hashes=pkgs/vendor-hashes.json
      tmp=$(mktemp -d)
      trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"' EXIT

      export GOTOOLCHAIN=local GO111MODULE=on GOFLAGS=-modcacherw
      export GOPATH="$tmp/gopath" GOCACHE="$tmp/gocache"

      json=$(cat "$hashes")
      for dir in "$@"; do
        real=$(realpath -e -- "$dir")
        case "$real" in
          "$root"/*) ;;
          *)
            echo "renovate-update-vendor-hash: $dir is outside the repository" >&2
            exit 1
            ;;
        esac
        if [ ! -f "$real/go.mod" ]; then
          echo "renovate-update-vendor-hash: $dir has no go.mod" >&2
          exit 1
        fi
        key=''${real#"$root"/}

        work=$(mktemp -d -p "$tmp")
        cp -rP "$real/." "$work"
        rm -rf "$work/vendor"
        (cd "$work" && go mod vendor)
        hash=$(nix --extra-experimental-features nix-command hash path --algo sha256 "$work/vendor")
        json=$(jq --arg key "$key" --arg hash "$hash" '.[$key] = $hash' <<<"$json")
      done
      jq --sort-keys . <<<"$json" >"$hashes"
    '';
  };

  configFile = pkgs.writeText "renovate-config.js" ''
    module.exports = {
        "endpoint": "${giteaUrl}/api/v1",
        "gitAuthor": "${gitAuthorName} <${gitAuthorEmail}>",
        "platform": "gitea",
        "onboardingConfigFileName": "renovate.json",
        "autodiscover": true,
        "optimizeForDisabled": true,
        "allowedCommands": ["^renovate-update-vendor-hash( |$)"],
        "customEnvVariables": { "GOTOOLCHAIN": "local" },
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

        updateVendorHash
      ];

      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;

        CacheDirectory = "renovate";
        WorkingDirectory = "%C/renovate";

        EnvironmentFile = config.age.secrets."renovate/environment".path;
        LoadCredential = "environment:${config.age.secrets."renovate/environment".path}";
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
