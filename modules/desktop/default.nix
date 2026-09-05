{ config, lib, ... }:

{
  imports = [
    ./automount.nix
    ./awesome
    ./sway
    ./timewall.nix
    ./firefox.nix
  ];
}
