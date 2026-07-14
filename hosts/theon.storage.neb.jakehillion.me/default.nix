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

    # This device is currently broken/offline, so its Nebula key couldn't be
    # grabbed for the ogygia-managed overlay. If it's brought back to life,
    # gather its pubkey and add it to the Ogygia-managed Nebula (set
    # ogygia.nebula.groups + pubKey, sign with `ogygia nebula rekey`) and drop
    # this override.
    ogygia.nebula.enable = lib.mkForce false;

    ## Custom Services
    custom = {
      locations.autoServe = true;
    };

    ## Networking
    networking.useNetworkd = true;
    systemd.network.enable = true;

    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
    networking.firewall = {
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
