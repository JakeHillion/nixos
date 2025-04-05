{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = lib.mkMerge [
    {
      ## Systemd-boot
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      ## Setup but don't enable tang, that depends on the device's location
      custom.tang = {
        networkingModule = "igc";
        secretFile = "/data/disk_encryption.jwe";
        devices = [ "disk0-crypt" ];
      };

      ## Get a serial console on ttyS0
      boot.kernelParams = [ "console=ttyS0,115200n8" ];

      ## Delegation
      custom.impermanence.enable = true;
    }

    (lib.mkIf config.custom.tang.enable {
      boot.kernelParams = [ "ip=dhcp" ];
    })
  ];
}
