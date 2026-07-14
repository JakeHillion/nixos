{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        dwJizOwI7tfcNVl/er9lzj98f26vfMtXebiUXAlSOwU=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    boot.kernelParams =
      let
        ifcfg = builtins.head config.networking.interfaces.enp6s0.ipv4.addresses;
      in
      [ "ip=${ifcfg.address}::${config.networking.defaultGateway.address}:255.255.255.192:${config.networking.hostName}:eth0:none" ];
    custom.tang = {
      enable = true;
      networkingModule = "igb";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" "disk2-crypt" ];
    };

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
    boot.initrd.systemd.services.reset-cache-subvolumes = {
      description = "Wipe /cache/{system,nix-builds} to empty snapshots before stage 2";
      wantedBy = [ "initrd.target" ];
      after = [ "cryptsetup.target" ];
      requires = [ "cryptsetup.target" ];
      before = [ "initrd-fs.target" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /reset-cache
        mount -t btrfs -o subvol=cache /dev/mapper/disk0-crypt /reset-cache

        btrfs subvolume delete /reset-cache/system
        btrfs subvolume snapshot /reset-cache/empty_snapshot /reset-cache/system

        btrfs subvolume delete /reset-cache/nix-builds
        btrfs subvolume snapshot /reset-cache/empty_snapshot /reset-cache/nix-builds
        chmod 0700 /reset-cache/nix-builds

        umount /reset-cache
      '';
    };
    nix = {
      distributedBuilds = true;
      settings = {
        builders-use-substitutes = true;
        build-dir = "/cache/nix-builds/";
      };
      buildMachines = [{
        hostName = "slider.pop.${config.ogygia.domain}";
        system = "aarch64-linux";
        protocol = "ssh-ng";
        maxJobs = 4;
        speedFactor = 1;
        supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
        sshUser = "nix-builder";
        sshKey = "${config.custom.impermanence.base}/system/etc/ssh/ssh_host_ed25519_key";
      }];
    };

    ## Custom Services
    custom = {
      locations.autoServe = true;
      www.global.enable = true;
      services = {
        gitea.actions = {
          enable = true;
          tokenSecret = ../../modules/services/gitea/actions/boron.age;
          capacity = 1;
          dockerMemoryHigh = 12 * 1024 * 1024 * 1024; # 8 GiB
        };
        gitea.actions-vm = {
          enable = true;
          instances = 3;
        };
        # Burst-to-cloud Gitea Actions runners.
        # See modules/services/gitea/actions-vm-burst/README.md.
        gitea.actions-vm-burst = {
          enable = true;
          gcpProject = "continuous-integration-498314";
          gcsBucket = "testquorum-ci-vm-images";
          hetzner.enable = true;
        };
        matrix.mautrix_discord = true;
      };
    };

    # Allow hosts running an internal-TLS service to reach the DNS-01 challenge
    # API. They pick up the acme-dns-client group automatically via the Caddy
    # modules (see modules/www/nebula.nix), so this grants access without
    # requiring the broad legacy-full-access group — the path for retiring it.
    ogygia.nebula.firewall.inbound = [
      { groups = [ "acme-dns-client" ]; port = "8553"; proto = "tcp"; }
    ];

    services.knot.settings.server.listen = [
      "138.201.252.214@53"
      "2a01:4f8:173:23d2::2@53"
    ];

    ## Filesystems
    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # By default both /data and /nix would be scrubbed. They are the same filesystem so this is wasteful.
      fileSystems = [ "/data" ];
    };

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

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
          ipv4.addresses = [{
            address = "138.201.252.214";
            prefixLength = 26;
          }];
          ipv6.addresses = [{
            address = "2a01:4f8:173:23d2::2";
            prefixLength = 64;
          }];
        };
      };
      defaultGateway = {
        address = "138.201.252.193";
        interface = "eth0";
      };
      defaultGateway6 = {
        address = "fe80::1";
        interface = "eth0";
      };
    };

    networking.firewall = {
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
            7654 # Tang
            8080 # Unifi (inform)
          ];
          allowedUDPPorts = lib.mkForce [
            53 # DNS
            443 # HTTP 3
            3478 # Unifi STUN
            4242 # Nebula Lighthouse
          ];
        };
      };
    };
  };
}
