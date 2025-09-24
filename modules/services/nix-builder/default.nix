{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.nix-builder;

  # Gitea configuration
  giteaUrl = "gitea.hillion.co.uk";
  giteaOwner = "JakeHillion";
  giteaRepo = "nixos";
  contextName = "nix-builder (${pkgs.stdenv.hostPlatform.system})";
in
{
  options.custom.services.nix-builder = {
    enable = lib.mkEnableOption "nix-builder";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "How often to run the builder after inactivity (systemd time format)";
    };

    atticCache = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
      description = "Name of the attic cache to push to";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."attic/client-token".file = ./client-token.age;
    age.secrets."nix-builder/gitea-token".file = ./gitea-token.age;

    systemd.services.nix-builder = {
      description = "Nix Builder Service";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        CacheDirectory = "nix-builder";
        WorkingDirectory = "%C/nix-builder";
        LoadCredential = [
          "attic-token:${config.age.secrets."attic/client-token".path}"
          "gitea-token:${config.age.secrets."nix-builder/gitea-token".path}"
        ];
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };

      environment = {
        HOME = "%C/nix-builder";
      };

      script = ''
        set -euo pipefail

        REPO_URL="gitea.hillion.co.uk/JakeHillion/nixos.git"
        REPO_DIR="nixos-repo"
        CURRENT_ARCH="${pkgs.stdenv.hostPlatform.system}"
        GITEA_URL="${giteaUrl}"
        GITEA_OWNER="${giteaOwner}"
        GITEA_REPO="${giteaRepo}"
        CONTEXT_NAME="${contextName}"
        GITEA_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/gitea-token")"

        echo "[>] Starting nix-builder run"

        # Function to update commit status in Gitea
        update_commit_status() {
          local commit_sha="$1"
          local state="$2"
          local description="$3"

          echo "[•] Updating commit status: $commit_sha -> $state: $description"

          ${pkgs.curl}/bin/curl -s -X POST \
            "https://$GITEA_URL/api/v1/repos/$GITEA_OWNER/$GITEA_REPO/statuses/$commit_sha" \
            -H "Authorization: token $GITEA_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
              \"context\": \"$CONTEXT_NAME\",
              \"description\": \"$description\",
              \"state\": \"$state\"
            }" || echo "[!] Failed to update commit status for $commit_sha"
        }

        # Track build results
        BUILD_FAILURES=()
        BUILD_SUCCESSES=()

        # Configure attic client
        ${pkgs.attic-client}/bin/attic login nixos http://attic.${config.ogygia.domain}/ "$(cat "$CREDENTIALS_DIRECTORY/attic-token")"

        # Clone or update repository
        if [[ ! -d "$REPO_DIR" ]]; then
          echo "[↓] Cloning repository..."
          ${pkgs.git}/bin/git clone "https://$REPO_URL" "$REPO_DIR"
          cd "$REPO_DIR"
        else
          echo "[↻] Updating repository..."
          cd "$REPO_DIR"
          ${pkgs.git}/bin/git remote set-url origin "https://$REPO_URL"
          ${pkgs.git}/bin/git fetch origin --prune
        fi

        # Get all remote branches
        REMOTE_BRANCHES=$(\
          ${pkgs.git}/bin/git for-each-ref --sort=-committerdate refs/remotes/ --format='%(refname:short)' \
          | ${pkgs.gnugrep}/bin/grep -v 'origin$' \
          | ${pkgs.gnused}/bin/sed 's|origin/||')

        for branch in $REMOTE_BRANCHES; do
          echo "[•] Processing branch: $branch"

          # Switch to detached head at remote branch
          ${pkgs.git}/bin/git switch --detach "origin/$branch"

          # Get current commit SHA for status updates
          COMMIT_SHA=$(${pkgs.git}/bin/git rev-parse HEAD)
          echo "[•] Commit SHA: $COMMIT_SHA"

          # Set status to pending
          update_commit_status "$COMMIT_SHA" "pending" "Build started"

          # Get all packages for current architecture
          echo "[•] Getting packages for $CURRENT_ARCH..."
          if ! PACKAGES=$(${pkgs.nix}/bin/nix flake show --json 2>/dev/null | ${pkgs.jq}/bin/jq -r ".packages.\"$CURRENT_ARCH\" // {} | keys[]"); then
            echo "Failed to get packages for branch $branch"
            exit 1
          fi

          # Get nixosConfigurations for current architecture
          echo "[•] Getting nixosConfigurations for $CURRENT_ARCH..."
          if ! ALL_NIXOS_CONFIGS=$(${pkgs.nix}/bin/nix flake show --json 2>/dev/null | ${pkgs.jq}/bin/jq -r ".nixosConfigurations // {} | keys[]"); then
            echo "Failed to get nixosConfigurations for branch $branch"
            exit 1
          fi

          # Filter by checking system files
          NIXOS_CONFIGS=""
          for config in $ALL_NIXOS_CONFIGS; do
            if ! SYSTEM=$(${pkgs.nix}/bin/nix eval --raw ".#nixosConfigurations.\"$config\".pkgs.system"); then
              echo "Failed to get system for configuration $config"
              exit 1
            fi
            if [[ "$SYSTEM" == "$CURRENT_ARCH" ]]; then
              NIXOS_CONFIGS="$NIXOS_CONFIGS $config"
            fi
          done

          # Build packages first
          PACKAGE_ARGS=()
          for package in $PACKAGES; do
            PACKAGE_ARGS+=(".#packages.$CURRENT_ARCH.\"$package\"")
          done

          # Add nixosConfigurations (already filtered by architecture)
          CONFIG_ARGS=()
          for config in $NIXOS_CONFIGS; do
            CONFIG_ARGS+=(".#nixosConfigurations.\"$config\".config.system.build.toplevel")
          done

          # Combine all buildable targets
          ALL_ARGS=("''${PACKAGE_ARGS[@]}" "''${CONFIG_ARGS[@]}")

          if [[ ''${#ALL_ARGS[@]} -eq 0 ]]; then
            echo "[!] No targets to build for branch $branch"
            continue
          fi

          echo "[•] Building ''${#ALL_ARGS[@]} targets"
          if ${pkgs.nix}/bin/nix build \
            --quiet \
            --no-link \
            --print-out-paths \
            "''${ALL_ARGS[@]}" \
          | ${pkgs.attic-client}/bin/attic push --stdin nixos; then
            echo "[+] Successfully built and uploaded branch $branch"
            BUILD_SUCCESSES+=("$branch")
            update_commit_status "$COMMIT_SHA" "success" "Build completed successfully"
          else
            st=("''${PIPESTATUS[@]}")
            if (( st[1] != 0 )); then
              echo "[x] Attic push failed for branch $branch"
              update_commit_status "$COMMIT_SHA" "failure" "Attic push failed"
              exit 1
            else
              echo "[!] Build failed for branch $branch"
              BUILD_FAILURES+=("$branch")
              update_commit_status "$COMMIT_SHA" "failure" "Build failed"
            fi
          fi
        done

        # Report results
        echo ""
        if [[ ''${#BUILD_SUCCESSES[@]} -gt 0 ]]; then
          echo "[•] Successful builds:"
          for branch in "''${BUILD_SUCCESSES[@]}"; do
            echo "  ✓ $branch"
          done
          echo ""
        fi
        if [[ ''${#BUILD_FAILURES[@]} -gt 0 ]]; then
          echo "[•] Failed builds:"
          for branch in "''${BUILD_FAILURES[@]}"; do
            echo "  ✗ $branch"
          done
          echo ""
        fi

        echo ""
        echo "[>] nix-builder run completed: ''${#BUILD_SUCCESSES[@]} successes, ''${#BUILD_FAILURES[@]} failures"
      '';
    };

    systemd.timers.nix-builder = {
      description = "Nix Builder Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30m";
        OnUnitInactiveSec = cfg.interval;
        RandomizedDelaySec = "10m";
      };
    };

    # Allow nix-builder to use nix daemon
    nix.settings.trusted-users = [ "nix-builder" ];
  };
}
