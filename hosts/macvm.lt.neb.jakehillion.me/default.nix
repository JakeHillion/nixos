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

    # Override Nebula lighthouse addresses due to DNS resolution issues
    networking.hosts = {
      "138.201.252.214" = [ "boron.cx.jakehillion.me" ];
      "185.240.111.53" = [ "home.jakehillion.me" ];
      "80.229.251.26" = [ "home.scott.hillion.co.uk" ];
    };
  };
}
