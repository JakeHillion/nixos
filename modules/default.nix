{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./chia.nix
    ./desktop/awesome/default.nix
    ./locations.nix
    ./resilio.nix
    ./services/mastodon/default.nix
    ./services/matrix.nix
    ./tailscale.nix
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
