{ config, pkgs, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/5/default.nix"
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostName = "sodium";
    networking.domain = "pop.neb.jakehillion.me";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Impermanence
    custom.impermanence = {
      enable = true;
      cache.enable = true;
    };
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      btrfs subvolume delete /cache/tmp
      btrfs subvolume snapshot /cache/empty_snapshot /cache/tmp
      chmod 1777 /cache/tmp
    '';

    ## CA server
    custom.ca.service.enable = true;

    ### nix only supports build-dir from 2.22. bind mount /tmp to something persistent instead.
    fileSystems."/tmp" = {
      device = "/cache/tmp";
      options = [ "bind" ];
    };
    # nix = {
    #   settings = {
    #     build-dir = "/cache/tmp/";
    #   };
    # };

    ## BTRFS Backups
    users.users."btrbk".uid = config.ids.uids.btrbk;
    users.groups."btrbk".gid = config.ids.gids.btrbk;

    services.btrbk.instances."data".settings = {
      raw_target_compress = "zstd";
      raw_target_encrypt = "gpg";
      gpg_recipient = "jake@hillion.co.uk";

      snapshot_dir = "/data/snapshots";

      subvolume."/data" = {
        target."raw ssh://phoenix.st.neb.jakehillion.me/practical-defiant-coffee/backups/btrbk/sodium.pop" = {
          ssh_user = "btrbk";
          ssh_identity = "/data/system/id_ecdsa_btrbk";
        };
      };
    };

    ## Custom Services
    custom.locations.autoServe = true;
    custom.www.home.enable = true;
    custom.www.iot.enable = true;
    custom.services.isponsorblocktv.enable = true;

    # Networking
    networking = {
      interfaces.end0.name = "eth0";
      vlans = {
        iot = {
          id = 2;
          interface = "eth0";
        };
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
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
            7654 # Tang
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
          ];
        };
        iot = {
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
          ];
        };
      };
    };

    ## Tailscale
    services.tailscale.enable = true;
  };
}
