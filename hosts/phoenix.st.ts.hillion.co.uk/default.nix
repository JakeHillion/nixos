{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostName = "phoenix";
    networking.domain = "st.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "ip=dhcp"
      "zfs.zfs_arc_max=34359738368"
    ];
    boot.initrd = {
      availableKernelModules = [ "igc" ];
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
    custom.locations.autoServe = true;
    custom.impermanence.enable = true;

    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # All filesystems includes the BTRFS parts of all the hard drives. This
      # would take forever and is redundant as they get fully read regularly.
      fileSystems = [ "/data" ];
    };

    ## Chia
    age.secrets."chia/farmer.key" = {
      file = ../../secrets/chia/farmer.key.age;
      owner = "chia";
      group = "chia";
    };
    custom.chia = {
      enable = true;
      keyFile = config.age.secrets."chia/farmer.key".path;
      plotDirectories = builtins.genList (i: "/mnt/d${toString i}/plots/contract-k32") 8;
    };

    ## Backups
    ### Git
    custom.backups.git = {
      enable = true;
      extraRepos = [ "https://gitea.hillion.co.uk/JakeHillion/nixos.git" ];
    };

    ## Networking
    networking = {
      interfaces.enp4s0.name = "eth0";
      interfaces.enp5s0.name = "eth1";
      interfaces.enp6s0.name = "eth2";
      interfaces.enp8s0.name = "eth3";
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [ ];
          allowedUDPPorts = lib.mkForce [ ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/phoenix.st.ts.hillion.co.uk".file = ../../secrets/tailscale/phoenix.st.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/phoenix.st.ts.hillion.co.uk".path;
    };
  };
}
