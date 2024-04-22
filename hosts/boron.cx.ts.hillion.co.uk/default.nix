{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "boron";
    networking.domain = "cx.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [ "ip=dhcp" ];
    boot.initrd = {
      availableKernelModules = [ "igb" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices = {
          "disk0-crypt".secretFile = ./disk_encryption.jwe;
          "disk1-crypt".secretFile = ./disk_encryption.jwe;
        };
      };
    };

    ## Impermanence
    custom.impermanence.enable = true;

    ## Custom Services
    custom = {
      locations.autoServe = true;
    };

    services.foldingathome = {
      enable = true;
      user = "JakeH"; # https://stats.foldingathome.org/donor/id/357021
      daemonNiceLevel = 19;
    };

    ## Enable ZRAM to help with root on tmpfs
    zramSwap = {
      enable = true;
      memoryPercent = 200;
      algorithm = "zstd";
    };

    ## Filesystems
    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # By default both /data and /nix would be scrubbed. They are the same filesystem so this is wasteful.
      fileSystems = [ "/data" ];
    };

    ## Networking
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
    };

    networking = {
      useDHCP = false;
      interfaces = {
        enp6s0 = {
          name = "eth0";
          useDHCP = true;
          ipv6.addresses = [{
            address = "2a01:4f8:173:23d2::2";
            prefixLength = 64;
          }];
        };
      };
      defaultGateway6 = {
        address = "fe80::1";
        interface = "eth0";
      };
    };

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/boron.cx.ts.hillion.co.uk".file = ../../secrets/tailscale/boron.cx.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/boron.cx.ts.hillion.co.uk".path;
      ipv4Addr = "100.112.54.25";
      ipv6Addr = "fd7a:115c:a1e0::2a01:3619";
    };
  };
}
