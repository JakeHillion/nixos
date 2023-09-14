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
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/jorah.cx.ts.hillion.co.uk".file = ../../secrets/tailscale/jorah.cx.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/jorah.cx.ts.hillion.co.uk".path;
    };
  };
}
