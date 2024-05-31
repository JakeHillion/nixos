{ config, pkgs, nixpkgs-unstable, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/5/default.nix"
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostName = "sodium";
    networking.domain = "pop.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Impermanence
    custom.impermanence.enable = true;
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      btrfs subvolume delete /cache/tmp
      btrfs subvolume snapshot /cache/empty_snapshot /cache/tmp
      chmod 0777 /cache/tmp
      chmod +t /cache/tmp
    '';

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

    ## Use ccache for building the Linux kernel
    programs.ccache.enable = true;
    nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];
    fileSystems."${config.programs.ccache.cacheDir}" = {
      device = "${config.custom.dns.authoritative.ipv4.uk.co.hillion.ts.storage.tywin}:/ccache";
      fsType = "nfs";
      options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
    };
    programs.ccache.packageNames = [
      # linux_rpi5 overrides from linux_rpi4
      "linux_rpi4"
    ];

    ## Custom Services
    custom.locations.autoServe = true;

    # Networking
    networking = {
      useDHCP = false;
      interfaces = {
        end0 = {
          name = "eth0";
          useDHCP = true;
        };
      };
    };
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = lib.mkForce [
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/sodium.pop.ts.hillion.co.uk".file = ../../secrets/tailscale/sodium.pop.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/sodium.pop.ts.hillion.co.uk".path;
    };
  };
}
