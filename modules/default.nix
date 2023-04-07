{ config, lib, ... }:

{
  imports = [
    ./www/global.nix
    ./www/www-repo.nix
  ];
}
