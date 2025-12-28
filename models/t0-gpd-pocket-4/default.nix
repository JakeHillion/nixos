{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    ## Laptop configuration
    custom.profiles.laptop = true;

    ## Boot
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ## AMD APU configuration
    boot.initrd.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    ## Console rotation
    boot.kernelParams = [ "fbcon=rotate:1" ];

    ## Display rotation for built-in screen
    # GPD Pocket 4 screen is rotated 90 degrees counter-clockwise by default
    custom.desktop.sway = {
      extraConfig = ''
        output * transform 90
      '';
      greeterRotation = "270";
    };

    ## Impermanence
    custom.impermanence.enable = true;
  };
}
