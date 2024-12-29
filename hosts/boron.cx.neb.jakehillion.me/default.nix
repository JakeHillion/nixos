{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "boron";
    networking.domain = "cx.neb.jakehillion.me";

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
    ### custom.sched_ext.enable implies >=6.12, if this is removed the kernel may need to be pinned again. >=6.10 seems good.
    custom.sched_ext.enable = true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Impermanence
    custom.impermanence = {
      enable = true;
      cache.enable = true;

      userExtraFiles.jake = [
        ".ssh/id_ecdsa"
        ".ssh/id_rsa"
      ];
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

    ## Resilio
    custom.resilio = {
      enable = true;
      folders =
        let
          folderNames = [
            "dad"
            "joseph"
            "projects"
            "resources"
            "sync"
          ];
          mkFolder = name: {
            name = name;
            secret = {
              name = "resilio/plain/${name}";
              file = ../../secrets/resilio/plain/${name}.age;
            };
          };
        in
        builtins.map (mkFolder) folderNames;
    };
    services.resilio.directoryRoot = "/data/sync";

    ## General usability
    ### Make podman available for dev tools such as act
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
      };
    };
    users.users.jake.extraGroups = [ "podman" ];

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
      trustedInterfaces = [ "tailscale0" "neb.jh" ];
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
            4242 # Nebula Lighthouse
          ];
        };
      };
    };

    ## Tailscale
    services.tailscale.enable = true;
  };
}