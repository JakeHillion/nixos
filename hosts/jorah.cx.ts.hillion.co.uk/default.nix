{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.05";

    networking.hostName = "jorah";
    networking.domain = "cx.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    ## Impermanence
    custom.impermanence.enable = true;

    ## Custom Services
    custom = {
      locations.autoServe = true;
      www.global.enable = true;
      services = {
        version_tracker.enable = true;
        gitea.actions = {
          enable = true;
          tokenSecret = ../../secrets/gitea/actions/jorah.age;
        };
      };
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
        enp5s0 = {
          name = "eth0";
          useDHCP = true;
          ipv6.addresses = [{
            address = "2a01:4f9:4b:3953::2";
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
      allowedTCPPorts = lib.mkForce [
        22 # SSH
        3022 # Gitea SSH (accessed via public 22)
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
            53 # DNS
            80 # HTTP 1-2
            443 # HTTPS 1-2
            8080 # Unifi (inform)
          ];
          allowedUDPPorts = lib.mkForce [
            53 # DNS
            443 # HTTP 3
            3478 # Unifi STUN
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/jorah.cx.ts.hillion.co.uk".file = ../../secrets/tailscale/jorah.cx.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/jorah.cx.ts.hillion.co.uk".path;
    };
  };
}
