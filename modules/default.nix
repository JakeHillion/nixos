{ config, lib, ... }:

{
  imports = [
    ./resilio.nix
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
