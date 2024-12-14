{ config, pkgs, lib, nixos-hardware, ... }:

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

    services.iodine.server = {
      enable = true;
      passwordFile = "/data/system/iodine.password";
      domain = "io.hillion.co.uk";
      ip = "172.16.10.1/24";
      extraConfig = "-c -n auto";
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
            53 # DNS
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
    age.secrets."tailscale/sodium.pop.ts.hillion.co.uk".file = ../../secrets/tailscale/sodium.pop.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/sodium.pop.ts.hillion.co.uk".path;
    };
  };
}
