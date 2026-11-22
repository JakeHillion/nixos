{ pkgs, modulesPath, ... }:

let
  authorizedKeys = import ../modules/ssh/authorized-keys.nix;

  issueAddresses = pkgs.writeShellApplication {
    name = "issue-addresses";
    runtimeInputs = [ pkgs.iproute2 pkgs.jq pkgs.util-linux ];
    text = ''
      update() {
        ip -json addr show \
          | jq -r '.[].addr_info[] | select(.scope != "host" and (.temporary or .deprecated or .tentative or .dadfailed | not)) | .local' \
          > /run/issue.d/50-addresses.issue.tmp
        echo >> /run/issue.d/50-addresses.issue.tmp
        mv /run/issue.d/50-addresses.issue.tmp /run/issue.d/50-addresses.issue
        agetty --reload
      }

      mkdir -p /run/issue.d
      update
      ip monitor address | while read -r _; do update; done
    '';
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal-combined.nix"
  ];

  users.users.nixos.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

  systemd.services.issue-addresses = {
    description = "Show the usable addresses at the login prompt";
    wantedBy = [ "multi-user.target" ];
    before = [ "getty.target" ];
    serviceConfig = {
      ExecStart = "${issueAddresses}/bin/issue-addresses";
      Restart = "always";
    };
  };
}
