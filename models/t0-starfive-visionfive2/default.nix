{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.grub.enable = false;

    # Delegation
    custom.impermanence.enable = true;
  };
}
