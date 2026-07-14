{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "25.11";

    custom.defaults = true;

    ogygia.nebula = {
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        feVWt36KaTvWq4HGDcSVw5De/bwhZInBP2Def1rjJAM=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    # fanboy lives behind the openclaw VLAN; cyclone.gw only permits LAN ->
    # fanboy Nebula on udp/4242, so pin the listen port (the ogygia module
    # defaults non-lighthouse hosts to an ephemeral port).
    services.nebula.networks.ogygia.listen.port = lib.mkForce 4242;

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
    custom.auto_updater.allowReboot = true;

    ogygia.hostinfod.enable = lib.mkForce false;
    custom.hostinfo.enable = lib.mkForce false;
  };
}
