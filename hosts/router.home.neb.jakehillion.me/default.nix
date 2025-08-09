{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.11";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;
    custom.impermanence.enable = true;
    custom.locations.autoServe = true;

    services.nsd.interfaces = [ "eth0" ];

    ## Interactive password
    custom.users.jake.password = true;

    ## Networking
    networking = {
      useDHCP = false;

      interfaces = {
        enp1s0 = {
          name = "eth0";
          useDHCP = true;
        };
        enp2s0 = { name = "eth1"; };
        enp3s0 = { name = "eth2"; };
        enp4s0 = { name = "eth3"; };
        enp5s0 = { name = "eth4"; };
        enp6s0 = { name = "eth5"; };
      };
    };

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
  };
}
