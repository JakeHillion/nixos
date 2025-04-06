{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./ca/default.nix
    ./chia.nix
    ./compressed_ram.nix
    ./defaults.nix
    ./desktop/default.nix
    ./dns.nix
    ./home/default.nix
    ./hostinfo.nix
    ./ids.nix
    ./impermanence.nix
    ./locations.nix
    ./nebula/default.nix
    ./oci-containers/default.nix
    ./prometheus/default.nix
    ./router.nix
    ./sched_ext.nix
    ./services/default.nix
    ./shell/default.nix
    ./ssh/default.nix
    ./storj.nix
    ./syncthing.nix
    ./tang/default.nix
    ./topology.nix
    ./users.nix
    ./www/default.nix
  ];

  options.custom = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "jake";
    };
  };
}
