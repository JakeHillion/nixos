{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "25.11";

    custom.defaults = true;

    ## Boot (single SSD, no mirrored boots)
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };

    ## Impermanence
    custom.impermanence.enable = true;

    ## Auto-updater with reboot
    custom.auto-updater.allowReboot = true;

    ## Force Nebula port for firewall rules on openclaw VLAN
    custom.nebula.forcePort = true;

    ## Disable services that require outbound Nebula connections
    ## (fanboy's Nebula cert blocks outbound to other Nebula hosts)
    services.journald.upload.enable = lib.mkForce false;
    custom.hostinfo.enable = lib.mkForce false;
  };
}
