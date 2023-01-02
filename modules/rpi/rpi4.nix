{ config, pkgs, lib, ... }:

{
  config.boot.loader.grub.enable = false;
  config.boot.loader.generic-extlinux-compatible.enable = true;
  config.boot.kernelPackages = pkgs.linuxPackages_rpi4;
}
