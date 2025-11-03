{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [ ".ssh/id_ecdsa" ".ssh/id_rsa" ];
    };

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # TODO: Fix btrfs subvolume rollback on boot. The boot.initrd.systemd.services.rollback
    # service does not work correctly on this VM.
  };
}
