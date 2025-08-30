{ config, pkgs, lib, ... }:

let
  cfg = config.custom.shell.update_scripts;

  update = pkgs.writeScriptBin "update" ''
    #! ${pkgs.runtimeShell}
    set -e

    if [[ $EUID -ne 0 ]]; then
      exec sudo ${pkgs.runtimeShell} "$0" "$@"
    fi

    # Create lock file to prevent auto_updater from running
    LOCK_FILE="/run/nixos-update.lock"
    echo "Creating update lock file..."
    touch "$LOCK_FILE"
    chown root:root "$LOCK_FILE"

    # Set up trap to clean up lock file on exit
    trap 'echo "Cleaning up lock file..."; rm -f "$LOCK_FILE"' EXIT

    # Wait for any currently running auto_updater service to stop
    if ${pkgs.systemd}/bin/systemctl is-active --quiet auto_updater.service; then
      echo "Waiting for auto_updater service to finish..."
      while ${pkgs.systemd}/bin/systemctl is-active --quiet auto_updater.service; do
        sleep 15
        echo "Still waiting for auto_updater to stop..."
      done
      echo "Auto_updater service has stopped."
    fi

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

    echo 'Building configuration...'
    nix build --no-link --print-out-paths '.#nixosConfigurations."${config.networking.fqdn}".config.system.build.toplevel' |& ${pkgs.nix-output-monitor}/bin/nom

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
