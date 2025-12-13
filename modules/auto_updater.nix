{ config, pkgs, lib, ... }:

let
  cfg = config.custom.auto_updater;
  location = "/etc/nixos";
  remote = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";
in
{
  options.custom.auto_updater = {
    enable = lib.mkEnableOption "www-repo";

    allowReboot = lib.mkOption {
      description = "Automatically reboot when an update changes the kernel.";
      default = false;
      type = lib.types.bool;
    };

    rebootDelay = lib.mkOption {
      description = "Time to wait before rebooting when kernel changes are detected (in minutes).";
      default = 15;
      type = lib.types.ints.unsigned;
      example = 10;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.allowReboot || cfg.rebootDelay < 30;
        message = "auto_updater.rebootDelay must be less than 30 minutes to avoid timer conflicts that could prevent rebooting.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${location} 0755 root root - -"
    ];

    systemd.timers.auto_updater = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15m";
        OnUnitInactiveSec = "60m";
        RandomizedDelaySec = "30m";
        Unit = "auto_updater.service";
      };
    };

    systemd.services.auto_updater = {
      description = "Automatically update NixOS configuration if already on main.";

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = [ pkgs.git ];

      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = location;
      };

      environment = {
        ALLOW_REBOOT = if cfg.allowReboot then "1" else "0";
      };

      script =
        let
          jj = lib.getExe pkgs.jujutsu;
          nixos-rebuild = lib.getExe pkgs.nixos-rebuild;
          readlink = "${pkgs.coreutils}/bin/readlink";
          shutdown = "${config.systemd.package}/bin/shutdown";
        in
        ''
          # Check for update lock file and exit early if it exists
          LOCK_FILE="/run/nixos-update.lock"
          if [ -f "$LOCK_FILE" ]; then
            # Verify the lock file was created by root for security
            if [ "$(stat -c %U "$LOCK_FILE" 2>/dev/null)" = "root" ]; then
              echo "Update lock file exists, manual update in progress. Exiting gracefully."
              exit 0
            fi
          fi

          if [ ! -d ".jj" ] && [ ! -d ".git" ]; then
              echo "Initializing new jj repository with git colocation..."
              ${jj} git clone ${remote} .
          elif [ ! -d ".jj" ] && [ -d ".git" ]; then
              echo "Initializing jj from existing git repository..."
              ${jj} git init
          elif [ -d ".jj" ] && [ ! -d ".git" ]; then
              echo "Enabling git colocation for existing jj repository..."
              ${jj} git colocation enable
          fi
 
          current_file="/run/current-system/sw/share/ogygia/build-revision"
          nextboot_file="/nix/var/nix/profiles/system/sw/share/ogygia/build-revision"

          if [ ! -f "$current_file" ] || [ ! -f "$nextboot_file" ]; then
            echo "Error: missing build-revision file." >&2
            exit 1
          fi

          current_sha="$(< "$current_file")"
          nextboot_sha="$(< "$nextboot_file")"

          ${jj} git fetch --remote origin

          is_in_main() {
            local ref="$1"
            # Try checking if it's a commit hash in main's ancestry
            ${jj} log -r "ancestors(main@origin) & $ref" --no-graph --limit 1 -T 'commit_id' 2>/dev/null | grep -q . && return 0
            # Try checking if it's a change-id in main's ancestry
            ${jj} log -r "ancestors(main@origin) & change_id($ref)" --no-graph --limit 1 -T 'commit_id' 2>/dev/null | grep -q . && return 0
            return 1
          }

          if ! is_in_main "$current_sha"; then
            echo "✖ current-system SHA $current_sha is NOT in origin/main. No rebuild."
            exit 0
          fi

          echo "✔ current-system SHA $current_sha is in origin/main."
          ${jj} new main@origin

          repo_sha="$(${jj} log -r 'main@origin' --no-graph -T 'commit_id')"

          if [ "$repo_sha" = "$current_sha" ] && [ "$repo_sha" = "$nextboot_sha" ]; then
            echo "✔ Already on correct commit. Nothing to do."
            exit 0
          fi

          if ! is_in_main "$nextboot_sha"; then
            echo "✱ next boot system SHA $nextboot_sha is NOT in origin/main. Running 'nixos-rebuild test'..."
            ${nixos-rebuild} --flake ".#${config.networking.fqdn}" test
            exit 0
          fi

          if [ "$ALLOW_REBOOT" != "1" ]; then
            echo "✔ next boot system SHA $nextboot_sha is in origin/main. Running 'nixos-rebuild switch'..."
            ${nixos-rebuild} --flake ".#${config.networking.fqdn}" switch
            exit 0
          fi

          echo "✔ next boot system SHA $nextboot_sha is in origin/main. Running 'nixos-rebuild boot'..."
          ${nixos-rebuild} --flake ".#${config.networking.fqdn}" boot

          booted="$(${readlink} /run/booted-system/{initrd,kernel,kernel-modules})"
          built="$(${readlink} /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"

          if [ "''${booted}" = "''${built}" ]; then
            echo "✔ No kernel/initrd changes detected. Switching to new generation..."
            ${nixos-rebuild} --flake ".#${config.networking.fqdn}" test
          else
            echo "⚠ Kernel/initrd changes detected. Rebooting in ${toString cfg.rebootDelay} minutes..."
            ${shutdown} -r +${toString cfg.rebootDelay}
          fi
        '';
    };
  };
}
