{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.05";

    networking.hostName = "jorah";
    networking.domain = "cx.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ## Impermanence
    custom.impermanence.enable = true;

    ## Custom Services
    custom = {
      locations.autoServe = true;
      services.version_tracker.enable = true;
      www.global.enable = true;
    };

    ## Filesystems
    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # By default both /data and /nix would be scrubbed. They are the same filesystem so this is wasteful.
      fileSystems = [ "/data" ];
    };

    ## Networking
    systemd.network = {
      enable = true;
      networks."enp5s0".extraConfig = ''
        [Match]
        Name = enp5s0
        [Network]
        Address = 2a01:4f9:4b:3953::2/64
        Gateway = fe80::1
      '';
    };

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        enp5s0 = {
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/jorah.cx.ts.hillion.co.uk".file = ../../secrets/tailscale/jorah.cx.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/jorah.cx.ts.hillion.co.uk".path;
      ipv4Addr = "100.96.143.138";
      ipv6Addr = "fd7a:115c:a1e0:ab12:4843:cd96:6260:8f8a";
    };
  };
}
