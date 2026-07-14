{ config, pkgs, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/4"
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    custom.defaults = true;

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        Qk1M4ogPm+jjfoxCBNz2/S053PHUPE76d6FEuA636VY=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Custom Services
    custom.auto_updater.allowReboot = true;
    custom.locations.autoServe = true;

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;

    # Networking
    networking.firewall = {
      interfaces = {
        "end0" = {
          allowedTCPPorts = [
            22 # SSH
            7654 # Tang
          ];
          allowedUDPPorts = [
            4242 # Nebula Lighthouse
          ];
        };
      };
    };
  };
}

