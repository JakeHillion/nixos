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

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.impermanence.enable = true;

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
      interfaces.enp1s0 = {
        name = "eth0";
        ipv4.addresses = [
          {
            address = "10.64.50.29";
            prefixLength = 24;
          }
        ];
      };
      # The vlan declaration auto-creates an empty networking.interfaces.eth0
      # entry; in nixpkgs 26.05's strict initrd networkd generator that
      # produced a second `40-eth0` network claiming DHCP=yes (no addresses)
      # while the enp1s0 rename produced DHCP=no. Pin both to no.
      interfaces.eth0.useDHCP = false;
      defaultGateway = "10.64.50.1";
      vlans = {
        iot = {
          id = 2;
          interface = "eth0";
        };
      };
      interfaces.iot = {
        ipv4.addresses = [
          {
            address = "10.239.19.8";
            prefixLength = 24;
          }
        ];
      };
    };
    # Force-accept RAs on eth0 despite forwarding=1 (set by OTBR for the
    # Thread mesh). Without this, eth0 ignores RAs and never SLAACs.
    boot.kernel.sysctl."net.ipv6.conf.eth0.accept_ra" = 2;

    # Use local dnsmasq as caching resolver
    networking.nameservers = lib.mkForce [ "127.0.0.1" ];

    # Configure dnsmasq as local caching DNS resolver
    services.dnsmasq = {
      enable = true;
      settings = {
        # Use external DNS servers for upstream resolution
        server = [ "1.1.1.1" "8.8.8.8" ];
        # Cache settings - larger cache for better performance
        cache-size = 10000;
        # Only bind to localhost to prevent external access
        listen-address = [ "127.0.0.1" "::1" ];
        bind-interfaces = true;
        # Don't read /etc/resolv.conf
        no-resolv = true;
        # Log queries for debugging (remove if not needed)
        log-queries = true;
      };
    };

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
            1400 # HA Sonos
            7654 # Tang
            21063 # HomeKit
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
            5353 # HomeKit / mDNS
            49191 # OTBR MeshCoP BorderAgent
          ];
        };
        iot = {
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
            5353 # mDNS (OTBR / Thread SRP)
          ];
        };
      };
    };
  };
}
