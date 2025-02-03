{ config, pkgs, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/4/default.nix"
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;

    ## Custom Services
    custom.locations.autoServe = true;

    ## Enable zram for 2GB Pi
    zramSwap = {
      enable = true;
      memoryPercent = 200;
      algorithm = "zstd";
    };

    # Networking
    networking.interfaces.end0.name = "eth0";
    networking.firewall = {
      trustedInterfaces = [ "neb.jh" ];
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

