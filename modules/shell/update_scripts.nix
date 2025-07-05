{ config, pkgs, lib, ... }:

let
  cfg = config.custom.shell.update_scripts;

  update = pkgs.writeScriptBin "update" ''
    #! ${pkgs.runtimeShell}
    set -e

    if [[ $EUID -ne 0 ]]; then
      exec sudo ${pkgs.runtimeShell} "$0" "$@"
    fi

    # Temporarily disable auto_updater to prevent racing
    echo "Temporarily disabling auto_updater service..."
    ${pkgs.systemd}/bin/systemctl stop auto_updater.timer 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl stop auto_updater.service 2>/dev/null || true

    # Set up trap to re-enable auto_updater on exit
    trap 'echo "Re-enabling auto_updater service..."; ${pkgs.systemd}/bin/systemctl start auto_updater.timer 2>/dev/null || true' EXIT

    if [ -n "$1" ]; then
      BRANCH=$1
    else
      BRANCH=main
    fi

    cd /etc/nixos
    if [ "$BRANCH" = "main" ]; then
      ${pkgs.git}/bin/git switch $BRANCH
      ${pkgs.git}/bin/git pull
    else
      ${pkgs.git}/bin/git fetch
      ${pkgs.git}/bin/git switch --detach origin/$BRANCH
    fi

    if ! ${pkgs.nixos-rebuild}/bin/nixos-rebuild --flake "/etc/nixos#${config.networking.fqdn}" test; then
      echo "WARNING: \`nixos-rebuild test' failed!"
    fi

    while true; do
      read -p "Do you want to boot this configuration? " yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit;;
          * ) echo "Please answer yes or no.";;
      esac
    done

    ${pkgs.nixos-rebuild}/bin/nixos-rebuild --flake "/etc/nixos#${config.networking.fqdn}" boot

    while true; do
      read -p "Would you like to reboot now? " yn
      case $yn in
          [Yy]* ) reboot;;
          [Nn]* ) exit;;
          * ) echo "Please answer yes or no.";;
      esac
    done
  '';
in
{
  options.custom.shell.update_scripts = {
    enable = lib.mkEnableOption "update_scripts";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      update
    ];
  };
}
