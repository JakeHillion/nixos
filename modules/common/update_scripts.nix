{ config, pkgs, lib, ... }:

let
  update = pkgs.writeScriptBin "update" ''
    #! ${pkgs.runtimeShell}
    set -e

    if [[ $EUID -ne 0 ]]; then
      exec sudo ${pkgs.runtimeShell} "$0" "$@"
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

    if ! ${pkgs.nixos-rebuild}/bin/nixos-rebuild --flake "/etc/nixos#${config.networking.fqdn}" test; then
      echo "WARNING: `nixos-rebuild test` failed!"
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
  config = {
    environment.systemPackages = [
      update
    ];
  };
}
