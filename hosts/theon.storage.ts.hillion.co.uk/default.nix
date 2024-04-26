{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "theon";
    networking.domain = "storage.ts.hillion.co.uk";

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

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
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/theon.storage.ts.hillion.co.uk".path;
      ipv4Addr = "100.104.142.22";
      ipv6Addr = "fd7a:115c:a1e0::4aa8:8e16";
    };

    ## Packages
    environment.systemPackages = with pkgs; [
      scrub
      smartmontools
    ];
  };
}
