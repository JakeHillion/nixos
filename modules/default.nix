{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./desktop/awesome/default.nix
    ./resilio.nix
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
