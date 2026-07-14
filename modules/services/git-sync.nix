{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.git-sync;
in
{
  options.custom.services.git-sync = {
    enable = lib.mkEnableOption "git repository sync service";

    repos = lib.mkOption {
      type = with lib.types; listOf (submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name for the repository (used for local directory)";
          };
          source = lib.mkOption {
            type = lib.types.str;
            description = "Source git remote URL to clone from";
          };
          destination = lib.mkOption {
            type = lib.types.str;
            description = "Destination git remote URL to push to";
          };
        };
      });
      readOnly = true;
      default = [
        {
          name = "nixos";
          source = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";
          # TODO: Use ssh://git@ssh.git.hillion.co.uk:3022/jh/nixos.git once public port forwarding works
          destination = "ssh://git@boron.cx.neb.jakehillion.me/jh/nixos.git";
        }
      ];
      description = "List of repositories to sync from source to destination";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."git/git_backups_ecdsa".file = ../../secrets/git/git_backups_ecdsa.age;

    systemd.services.git-sync = {
      description = "Git repository sync service - syncs repos to gitolite";

      serviceConfig = {
        DynamicUser = true;

        CacheDirectory = "git-sync";
        WorkingDirectory = "%C/git-sync";

        LoadCredential = [
          "id_ecdsa:${config.age.secrets."git/git_backups_ecdsa".path}"
        ];
      };

      environment = {
        GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i %d/id_ecdsa -o StrictHostKeyChecking=no";
      };

      script = ''
        set -euo pipefail

        echo "Starting git sync service..."

        # Define repos as associative array: [name]="source destination"
        declare -A repos=(
          ${lib.strings.concatStringsSep "\n          " (builtins.map (repo: "[\"${repo.name}\"]=\"${repo.source} ${repo.destination}\"") cfg.repos)}
        )

        # Clean up existing repos that are no longer configured
        for d in */; do
          if [ -d "$d" ]; then
            d="''${d%/}"
            if [ -z "''${repos[$d]:-}" ]; then
              echo "$d no longer configured, cleaning up..."
              rm -rf "$d"
            fi
          fi
        done

        # Process each repo
        EXIT_CODE=0
        for repo_name in "''${!repos[@]}"; do
          repo_info="''${repos[$repo_name]}"
          source_url="''${repo_info% *}"
          dest_url="''${repo_info##* }"
          
          echo "Processing $repo_name..."
          echo "  Source: $source_url"
          echo "  Destination: $dest_url"

          # Clone or update local mirror
          if [ -d "$repo_name" ]; then
            echo "  Updating existing mirror..."
            if ! (cd "$repo_name" && ${pkgs.git}/bin/git remote set-url origin "$source_url" && ${pkgs.git}/bin/git remote update --prune); then
              echo "  Failed to update $repo_name"
              EXIT_CODE=1
              continue
            fi
          else
            echo "  Cloning new mirror..."
            if ! ${pkgs.git}/bin/git clone --mirror "$source_url" "$repo_name"; then
              echo "  Failed to clone $repo_name"
              EXIT_CODE=1
              continue
            fi
          fi

          # Push to destination
          echo "  Pushing to destination..."
          if ! (cd "$repo_name" && ${pkgs.git}/bin/git push --mirror "$dest_url" 2>/dev/null || ${pkgs.git}/bin/git push --mirror "$dest_url"); then
            echo "  Failed to push $repo_name to destination"
            EXIT_CODE=1
          else
            echo "  Successfully synced $repo_name"
          fi
        done

        if [ $EXIT_CODE -ne 0 ]; then
          echo "Some repositories failed to sync!"
          exit $EXIT_CODE
        fi

        echo "Git sync service completed successfully"
      '';
    };

    systemd.timers.git-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitInactiveSec = "15m";
        RandomizedDelaySec = "5m";
      };
    };
  };
}
