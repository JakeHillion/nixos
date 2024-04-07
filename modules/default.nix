{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./chia.nix
    ./common/hostinfo.nix
    ./desktop/awesome/default.nix
    ./ids.nix
    ./impermanence.nix
    ./locations.nix
    ./resilio.nix
    ./services/default.nix
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
