{ config, lib, ... }:

{
  imports = [
    ./global.nix
    ./nebula.nix
    ./www-repo.nix
  ];
}
