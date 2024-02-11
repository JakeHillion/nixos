{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "theon";
    networking.domain = "storage.ts.hillion.co.uk";

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    custom.defaults = true;

    ## Custom Services
    custom = {
      locations.autoServe = true;
    };

    ## Networking
    systemd.network.enable = true;

    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
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

    ## Tailscale
    age.secrets."tailscale/theon.storage.ts.hillion.co.uk".file = ../../secrets/tailscale/theon.storage.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/theon.storage.ts.hillion.co.uk".path;
    };

    ## Packages
    environment.systemPackages = with pkgs; [
      scrub
      smartmontools
    ];
  };
}
