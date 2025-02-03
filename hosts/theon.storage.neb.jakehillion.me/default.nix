{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    custom.defaults = true;

    ## Custom Services
    custom = {
      locations.autoServe = true;
    };

    ## Networking
    networking.useNetworkd = true;
    systemd.network.enable = true;

    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
    networking.firewall = {
      trustedInterfaces = [ "neb.jh" ];
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        end0 = {
          allowedTCPPorts = lib.mkForce [ ];
          allowedUDPPorts = lib.mkForce [ ];
        };
      };
    };

    ## Packages
    environment.systemPackages = with pkgs; [
      scrub
      smartmontools
    ];
  };
}
