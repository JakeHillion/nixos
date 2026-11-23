{ config, pkgs, lib, modulesPath, ... }:

let
  authorizedKeys = import ../modules/ssh/authorized-keys.nix;

  splash = pkgs.writeShellApplication {
    name = "installer-splash";
    runtimeInputs = [ pkgs.coreutils pkgs.iproute2 pkgs.jq pkgs.ncurses ];
    text = ''
      addresses() {
        ip -json addr show \
          | jq -r '.[].addr_info[] | select(.scope != "host" and (.temporary or .deprecated or .tentative or .dadfailed | not)) | .local'
      }

      centre() {
        local cols
        cols=$(tput cols)
        printf '%*s%s\n' $(((cols - ''${#1}) / 2)) "" "$1"
      }

      draw() {
        local lines=("$@") rows
        rows=$(tput lines)
        tput clear
        printf '%*s' $(((rows - ''${#lines[@]} - 6) / 2)) "" | tr ' ' '\n'
        tput bold
        centre "${config.system.nixos.distroName} ${config.system.nixos.label} installer"
        tput sgr0
        echo
        echo
        if [ ''${#lines[@]} -eq 0 ]; then
          centre "Waiting for an address..."
        fi
        for line in "''${lines[@]}"; do
          tput bold
          centre "$line"
          tput sgr0
        done
        echo
        echo
        centre "Press Enter for a shell"
      }

      tput civis
      shown=""
      while true; do
        current=$(addresses)
        if [ "$current" != "$shown" ]; then
          mapfile -t lines <<<"$current"
          [ -z "$current" ] && lines=()
          draw "''${lines[@]}"
          shown=$current
        fi
        if read -rs -t 1 -n 1 key && [ -z "$key" ]; then
          break
        fi
      done

      tput cnorm
      tput clear
      exec ${pkgs.shadow}/bin/login -f root
    '';
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal-combined.nix"
  ];

  users.users.nixos.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

  console = {
    font = "ter-v32b";
    packages = [ pkgs.terminus_font ];
  };

  services.getty = {
    autologinUser = lib.mkForce null;
    helpLine = lib.mkForce ''
      SSH keys are authorised for "nixos" and "root". Both have an empty
      password at the console.

      To set up a wireless connection, run `nmtui`.
    '';
  };

  systemd.services."getty@tty1" = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStart = [
      ""
      (lib.getExe splash)
    ];
  };
}
