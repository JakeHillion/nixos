{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      # zswap
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.impermanence.enable = true;
    custom.services.isponsorblocktv.enable = true;

    custom.tang = {
      enable = true;
      networkingModule = "r8169";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" ];
    };

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
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
            1400 # HA Sonos
            21063 # HomeKit
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
            5353 # HomeKit
          ];
        };
        iot = {
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
          ];
        };
      };
    };
  };
}
