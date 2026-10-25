{ config, lib, ... }:

{
  imports = [
    ./backups
    ./compressed_ram.nix
    ./defaults.nix
    ./desktop
    ./dns
    ./games
    ./home
    ./ids.nix
    ./impermanence.nix
    ./locations.nix
    ./networking
    ./ogygia
    ./profiles
    ./prometheus
    ./qnap-display.nix
    ./rekey.nix
    ./sched_ext.nix
    ./services
    ./shell
    ./ssh
    ./storj.nix
    ./syncthing
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
