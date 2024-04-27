{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./chia.nix
    ./defaults.nix
    ./desktop/awesome/default.nix
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
    ./tailscale.nix
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
