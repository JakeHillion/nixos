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
      "ip=dhcp"
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

    # BeeLink GTi14 has stability issues on >=6.12 (and probably a bit before).
    # Pin to the last LTS for now, even though the performance is quite bad on
    # this hardware.
    boot.kernelPackages = pkgs.linuxPackages_6_6;

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.home.devbox = true;

    custom.users.jake.password = true;
    security.sudo.wheelNeedsPassword = lib.mkForce true;
    custom.desktop.sway.enable = true;

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

    ## Udisks
    services.udisks2.enable = true;

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## Spotify
    services.pipewire.enable = lib.mkForce false;
    hardware.pulseaudio.enable = true;
    users.users.jake.extraGroups = [ "audio" ];

    home-manager.users.jake.services.spotifyd = {
      enable = true;
      settings = {
        global = {
          device_name = "merlin.rig";
          device_type = "computer";
          bitrate = 320;

          backend = "pulseaudio";
        };
      };
    };

    # Networking
    networking = {
      interfaces.enp171s0.name = "eth0";
      interfaces.enp172s0.name = "eth1";
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
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
  };
}
