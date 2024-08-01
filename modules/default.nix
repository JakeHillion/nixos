{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./ca/default.nix
    ./chia.nix
    ./defaults.nix
    ./desktop/awesome/default.nix
    ./dns.nix
    ./home/default.nix
    ./hostinfo.nix
    ./ids.nix
    ./impermanence.nix
    ./locations.nix
    ./resilio.nix
    ./services/default.nix
    ./shell/default.nix
    ./ssh/default.nix
    ./storj.nix
    ./users.nix
    ./www/global.nix
    ./www/www-repo.nix
  ];

  options.custom = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "jake";
    };
  };
}
