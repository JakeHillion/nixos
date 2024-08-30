{ config, pkgs, lib, ... }:

{
  imports = [
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
          "disk0-crypt".secretFile = "/data/disk_encryption.jwe";
          "disk1-crypt".secretFile = "/data/disk_encryption.jwe";
        };
      };
    };

    custom.defaults = true;

    ## Kernel
    ### Explicitly use the latest kernel at time of writing because the LTS
    ### kernels available in NixOS do not seem to support this server's very
    ### modern hardware.
    boot.kernelPackages = pkgs.linuxPackages_6_10;
    ### Apply patch to enable sched_ext which isn't yet available upstream.
    boot.kernelPatches = [{
      name = "sched_ext";
      patch = pkgs.fetchpatch {
        url = "https://github.com/sched-ext/scx-kernel-releases/releases/download/v6.10.3-scx1/linux-v6.10.3-scx1.patch.zst";
        hash = "sha256-c4UlXsVOHGe0gvL69K9qTMWqCR8as25qwhfNVxCXUTs=";
        decode = "${pkgs.zstd}/bin/unzstd";
        excludes = [ "Makefile" ];
      };
      extraConfig = ''
        BPF y
        BPF_EVENTS y
        BPF_JIT y
        BPF_SYSCALL y
        DEBUG_INFO_BTF y
        FTRACE y
        SCHED_CLASS_EXT y
      '';
    }];

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Impermanence
    custom.impermanence = {
      enable = true;
      cache.enable = true;
    };
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      btrfs subvolume delete /cache/system
      btrfs subvolume snapshot /cache/empty_snapshot /cache/system
    '';

    ## Custom Services
    custom = {
      locations.autoServe = true;
      www.global.enable = true;
      services = {
        gitea.actions = {
          enable = true;
          tokenSecret = ../../secrets/gitea/actions/boron.age;
        };
      };
    };

    services.nsd.interfaces = [
      "138.201.252.214"
      "2a01:4f8:173:23d2::2"
    ];

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
            22 # SSH
            3022 # SSH (Gitea) - redirected to 22
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
    age.secrets."tailscale/boron.cx.ts.hillion.co.uk".file = ../../secrets/tailscale/boron.cx.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/boron.cx.ts.hillion.co.uk".path;
    };
  };
}
