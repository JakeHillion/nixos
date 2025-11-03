{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.impermanence.enable = true;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # TODO: Fix btrfs subvolume rollback on boot. The boot.initrd.systemd.services.rollback
    # service does not work correctly on this VM.
  };
}
