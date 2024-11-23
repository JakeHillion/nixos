{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostName = "stinger";
    networking.domain = "pop.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "ip=dhcp"

      # zswap
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];
    boot.initrd = {
      availableKernelModules = [ "r8169" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices = {
          "disk0-crypt".secretFile = "/data/disk_encryption.jwe";
        };
      };
    };

    custom.defaults = true;
    custom.impermanence.enable = true;
    custom.kernel.enable = true;
    custom.locations.autoServe = true;

    hardware = {
      bluetooth.enable = true;
    };

    # Networking
    networking = {
      interfaces.enp1s0.name = "eth0";
      vlans = {
        iot = {
          id = 2;
          interface = "eth0";
        };
      };
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
            1400 # HA Sonos
            21063 # HomeKit
          ];
          allowedUDPPorts = lib.mkForce [
            5353 # HomeKit
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/stinger.pop.ts.hillion.co.uk".file = ../../secrets/tailscale/stinger.pop.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/stinger.pop.ts.hillion.co.uk".path;
    };
  };
}
