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

      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = location;
      };

      environment = {
        ALLOW_REBOOT = if cfg.allowReboot then "1" else "0";
      };

      script =
        let
          git = lib.getExe pkgs.git;
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

          if [ ! -d ".git" ] ; then
              ${git} clone ${remote} .
          fi

          current_file="/run/current-system/etc/flake-version"
          nextboot_file="/nix/var/nix/profiles/system/etc/flake-version"

          if [ ! -f "$current_file" ] || [ ! -f "$nextboot_file" ]; then
            echo "Error: missing flake-version file." >&2
            exit 1
          fi

          current_sha="$(< "$current_file")"
          nextboot_sha="$(< "$nextboot_file")"

          ${git} fetch origin main

          is_in_main() {
            ${git} merge-base --is-ancestor "$1" origin/main
          }

          if ! is_in_main "$current_sha"; then
            echo "✖ current-system SHA $current_sha is NOT in origin/main. No rebuild."
            exit 0
          fi

          echo "✔ current-system SHA $current_sha is in origin/main."
          ${git} switch main
          ${git} pull

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
