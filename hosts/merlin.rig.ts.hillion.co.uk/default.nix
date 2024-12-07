{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostName = "merlin";
    networking.domain = "rig.ts.hillion.co.uk";

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
    custom.impermanence.enable = true;

    custom.users.jake.password = true;
    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Video drivers when docked
    boot.initrd.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    # TODO: move and impermanence me
    programs.kdeconnect.enable = true;
    home-manager.users."jake".services.kdeconnect.enable = true;
    hardware.uinput.enable = true;
    users.users."jake".extraGroups = [ "uinput" ];

    # Networking
    networking = {
      interfaces.enp171s0.name = "eth0";
      interfaces.enp172s0.name = "eth1";
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedTCPPortRanges = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ ];
      allowedUDPPortRanges = lib.mkForce [ ];

      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [ ];
          allowedTCPPortRanges = lib.mkForce [
            { from = 1714; to = 1764; } # KDE Connect
          ];
          allowedUDPPorts = lib.mkForce [ ];
          allowedUDPPortRanges = lib.mkForce [
            { from = 1714; to = 1764; } # KDE Connect
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/merlin.rig.ts.hillion.co.uk".file = ../../secrets/tailscale/merlin.rig.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/merlin.rig.ts.hillion.co.uk".path;
    };
  };
}
