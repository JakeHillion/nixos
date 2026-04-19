{ config, lib, ... }:

{
  imports = [
    ./auto_updater.nix
    ./backups
    ./ca
    ./chia.nix
    ./compressed_ram.nix
    ./defaults.nix
    ./desktop
    ./dns.nix
    ./games
    ./home
    ./hostinfo.nix
    ./ids.nix
    ./impermanence.nix
    ./locations.nix
    ./nebula
    ./networking
    ./oci-containers
    ./ogygia.nix
    ./profiles
    ./prometheus
    ./qnap-display.nix
    ./rekey.nix
    ./sched_ext.nix
    ./services
    ./shell
    ./ssh
    ./storj.nix
    ./syncthing.nix
    ./tang
    ./users.nix
    ./www
  ];

  options.custom = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "jake";
    };
  };
}
