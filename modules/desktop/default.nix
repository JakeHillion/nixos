{ config, lib, ... }:

{
  imports = [
    ./awesome
    ./sway
    ./timewall.nix
    ./firefox.nix
  ];
}
