{ config, pkgs, lib, ... }:

{
  imports = [
    ./bluetooth.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.05";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    boot.kernelParams = [
      # for tang - no idea why this is needed
      "ip=dhcp"
    ];
    custom.tang = {
      enable = true;
      networkingModule = "r8169";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "root" ];
    };

    ## Custom scheduler
    custom.sched_ext.enable = true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_rsa"
        ".ssh/id_ecdsa"
      ];
      userExtraDirs.jake = [
        ".local/share/PrismLauncher"
      ];
    };

    ## Enable ZRAM swap to help with root on tmpfs
    zramSwap = {
      enable = true;
      memoryPercent = 200;
      algorithm = "zstd";
    };

    # Allow performing aarch64 builds in QEMU
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## Resilio
    custom.resilio.enable = false;
    services.resilio.directoryRoot = "/data/sync";

    custom.resilio.folders =
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

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Networking
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
        iot = {
          allowedTCPPorts = lib.mkForce [
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
      };
    };
  };
}
