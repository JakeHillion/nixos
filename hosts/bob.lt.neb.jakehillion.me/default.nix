{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-gpd-pocket-4
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;
    custom.home.devbox = true;
    custom.home.neomutt.backup = false;
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Run latest kernel for sched_ext
    boot.kernelPackages = pkgs.linuxPackages_latest;

    ## Impermanence
    custom.impermanence = {
      enable = true;

      userExtraFiles.jake = [
        ".ssh/id_ecdsa"
      ];
    };

    ## WiFi
    age.secrets."wifi/bob.lt.${config.ogygia.domain}".file = ../../secrets/wifi/bob.lt.${config.ogygia.domain}.age;
    networking.wireless = {
      enable = true;
      secretsFile = config.age.secrets."wifi/bob.lt.${config.ogygia.domain}".path;

      networks = {
        "Hillion WPA3 Network".pskRaw = "ext:HILLION_WPA3_NETWORK_PSK";
      };
    };

    ## iPhone wired hotspot
    services.usbmuxd.enable = true;

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.sway.enable = true;

    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## Networking
    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
    };
  };
}
