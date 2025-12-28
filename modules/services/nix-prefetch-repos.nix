{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.nix-prefetch-repos;
in
{
  options.custom.services.nix-prefetch-repos = {
    enable = lib.mkEnableOption "nix-prefetch-repos";

    reposPath = lib.mkOption {
      type = lib.types.path;
      description = "Path to the directory containing git repositories to archive";
      example = "/data/users/jake/repos";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "User to run the service as (must have read access to reposPath)";
      example = "jake";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nix-prefetch-repos = {
      description = "Archive Nix flakes from git repositories to prevent GC";

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        CacheDirectory = "nix-prefetch-repos";
        CacheDirectoryMode = "0700";
      };

      script = ''
        set -euo pipefail

        REPOS_PATH="${cfg.reposPath}"
        ROOTS_DIR="$CACHE_DIRECTORY"

        echo "[>] Starting nix-prefetch-repos"
        echo "[*] Repos path: $REPOS_PATH"
        echo "[*] Roots directory: $ROOTS_DIR"

        # Track which roots we've created/updated this run
        declare -A ACTIVE_ROOTS

        archive_flake() {
          local flake_ref="$1"
          local root_path="$2"

          if output=$(${pkgs.nix}/bin/nix flake archive --json "$flake_ref" 2>/dev/null); then
            store_path=$(echo "$output" | ${pkgs.jq}/bin/jq -r '.path')
            if [[ -n "$store_path" && "$store_path" != "null" ]]; then
              ln -sfn "$store_path" "$root_path"
              return 0
            fi
          fi
          return 1
        }

        # Find all git repositories
        for repo_path in "$REPOS_PATH"/*/; do
          repo_path="''${repo_path%/}"
          repo_name="$(basename "$repo_path")"

          # Skip if not a git repo
          if [[ ! -d "$repo_path/.git" ]]; then
            echo "[*] Skipping $repo_name (not a git repo)"
            continue
          fi

          echo "[*] Processing repository: $repo_name"

          # Determine flake path by checking .envrc
          flake_subdir=""
          if [[ -f "$repo_path/.envrc" ]]; then
            # Extract path from "use flake <path>" directive
            flake_subdir=$(${pkgs.gnugrep}/bin/grep -oP '^\s*use\s+flake\s+\K\S+' "$repo_path/.envrc" 2>/dev/null || true)
            # Normalize: remove leading ./ if present
            flake_subdir="''${flake_subdir#./}"
            # Treat "." as empty (root)
            if [[ "$flake_subdir" == "." ]]; then
              flake_subdir=""
            fi
          fi

          if [[ -n "$flake_subdir" ]]; then
            echo "[*]   Flake in subdirectory: $flake_subdir"
            flake_base="$repo_path/$flake_subdir"
          else
            flake_base="$repo_path"
          fi

          # Skip if no flake.nix
          if [[ ! -f "$flake_base/flake.nix" ]]; then
            echo "[*] Skipping $repo_name (no flake.nix)"
            continue
          fi

          # Create repo-specific roots directory
          repo_roots_dir="$ROOTS_DIR/$repo_name"
          mkdir -p "$repo_roots_dir"

          # Archive HEAD (current working tree state)
          echo "[*]   Archiving HEAD"
          head_root="$repo_roots_dir/HEAD"
          if archive_flake "$flake_base" "$head_root"; then
            ACTIVE_ROOTS["$repo_name/HEAD"]=1
            echo "[+]   Archived HEAD"
          else
            echo "[!]   Failed to archive HEAD"
          fi

          # Get all local branches
          branches=$(cd "$repo_path" && ${pkgs.git}/bin/git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null || true)

          for branch in $branches; do
            echo "[*]   Archiving branch: $branch"

            # Sanitize branch name for filesystem (replace / with -)
            safe_branch="''${branch//\//-}"
            root_path="$repo_roots_dir/$safe_branch"

            # Build the flake reference with branch
            if [[ -n "$flake_subdir" ]]; then
              flake_ref="git+file://$repo_path?ref=$branch&dir=$flake_subdir"
            else
              flake_ref="git+file://$repo_path?ref=$branch"
            fi

            if archive_flake "$flake_ref" "$root_path"; then
              ACTIVE_ROOTS["$repo_name/$safe_branch"]=1
              echo "[+]   Archived $branch"
            else
              echo "[!]   Failed to archive $branch"
            fi
          done
        done

        # Clean up stale roots
        echo "[*] Cleaning up stale roots..."
        for repo_dir in "$ROOTS_DIR"/*/; do
          [[ -d "$repo_dir" ]] || continue
          repo_name="$(basename "$repo_dir")"

          for root_link in "$repo_dir"/*; do
            [[ -e "$root_link" || -L "$root_link" ]] || continue
            branch_name="$(basename "$root_link")"
            key="$repo_name/$branch_name"

            if [[ -z "''${ACTIVE_ROOTS[$key]:-}" ]]; then
              echo "[*]   Removing stale root: $root_link"
              rm -f "$root_link"
            fi
          done

          # Remove empty repo directories
          if [[ -z "$(ls -A "$repo_dir" 2>/dev/null)" ]]; then
            echo "[*]   Removing empty directory: $repo_dir"
            rmdir "$repo_dir" 2>/dev/null || true
          fi
        done

        echo "[>] nix-prefetch-repos completed"
      '';
    };

    systemd.timers.nix-prefetch-repos = {
      description = "Timer for nix-prefetch-repos service";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitInactiveSec = "4h";
        RandomizedDelaySec = "5m";
      };
    };

    nix.settings.trusted-users = [ cfg.user ];
  };
}
