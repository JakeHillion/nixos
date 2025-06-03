{ config, pkgs, lib, ... }:

let
  cfg = config.custom.auto_updater;
  location = "/etc/nixos";
  remote = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";
in
{
  options.custom.auto_updater = {
    enable = lib.mkEnableOption "www-repo";
  };

  config = lib.mkIf cfg.enable {
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

      script = with pkgs; ''
        if [ ! -d ".git" ] ; then
            ${git}/bin/git clone ${remote} .
        fi

        current_file="/nix/var/nix/gcroots/current-system/etc/flake-version"
        booted_file="/nix/var/nix/gcroots/booted-system/etc/flake-version"

        if [ ! -f "$current_file" ] || [ ! -f "$booted_file" ]; then
          echo "Error: missing flake-version file." >&2
          exit 1
        fi

        current_sha="$(< "$current_file")"
        booted_sha="$(< "$booted_file")"

        ${git}/bin/git fetch origin main

        is_in_main() {
          ${git}/bin/git merge-base --is-ancestor "$1" origin/main
        }

        if ! is_in_main "$current_sha"; then
          echo "✖ current-system SHA $current_sha is NOT in origin/main. No rebuild."
          exit 0
        fi

        echo "✔ current-system SHA $current_sha is in origin/main."
        ${git}/bin/git switch main
        ${git}/bin/git pull

        if is_in_main "$booted_sha"; then
          echo "✔ booted-system SHA $booted_sha is in origin/main. Running 'nixos-rebuild switch'..."
          ${nixos-rebuild}/bin/nixos-rebuild switch
        else
          echo "✱ booted-system SHA $booted_sha is NOT in origin/main. Running 'nixos-rebuild test'..."
          ${nixos-rebuild}/bin/nixos-rebuild test
        fi
      '';
    };
  };
}
