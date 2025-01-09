{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostName = "merlin";
    networking.domain = "rig.neb.jakehillion.me";

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
      availableKernelModules = [ "igc" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices = {
          "disk0-crypt".secretFile = "/data/disk_encryption.jwe";
        };
      };
    };

    boot.kernelPackages = pkgs.linuxPackages_latest;

    custom.defaults = true;
    custom.locations.autoServe = true;

    custom.users.jake.password = true;
    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [ ".ssh/id_ecdsa" ];
    };

    ## Video drivers when docked
    boot.initrd.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    # Allow performing aarch64 builds in QEMU
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    # Networking
    networking = {
      interfaces.enp171s0 = {
        name = "eth0";
        useDHCP = true;
      };
      interfaces.enp172s0 = {
        name = "eth1";
        useDHCP = false;
      };
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" "neb.jh" ];
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [ ];
          allowedUDPPorts = lib.mkForce [ ];
        };
      };
    };

    ## Tailscale
    services.tailscale.enable = true;
  };
}
