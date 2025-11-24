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
    ./laptop.nix
    ./locations.nix
    ./nebula
    ./oci-containers
    ./prometheus
    ./profiles
    ./qnap-display.nix
    ./router.nix
    ./sched_ext.nix
    ./services
    ./shell
    ./ssh
    ./storj.nix
    ./syncthing.nix
    ./tang
    ./topology.nix
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
