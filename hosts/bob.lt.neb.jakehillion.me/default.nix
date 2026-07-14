{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-gpd-pocket-4
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;
    custom.profiles.devbox = true;
    custom.home.neomutt.backup = false;
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Run latest kernel for sched_ext
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Extra packages
    environment.systemPackages = with pkgs; [
      vlc # for using the inbuilt KVM
      obsidian
    ];

    ## Impermanence
    custom.impermanence = {
      enable = true;

      userExtraFiles.jake = [
        ".ssh/id_ecdsa"
        ".ssh/id_rsa"
      ];
    };

    ## Bluetoooth
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;

    ## WiFi
    age.secrets."wifi".file = ./wifi.env.age;
    networking.wireless = {
      enable = true;
      secretsFile = config.age.secrets."wifi".path;

      networks = {
        "Hillion WPA3 Network".pskRaw = "ext:HILLION_WPA3_NETWORK_PSK";
        "some-windburned-bisection".pskRaw = "ext:STARLINK_PSK";
        "Hyperoptic Fibre D584 5ghz".pskRaw = "ext:HYPEROPTIC_PSK";
        "instructional-blank-cursor" = {
          pskRaw = "ext:TRAVEL_PSK";
          priority = 10;
        };

        "Jake’s iPhone" = {
          pskRaw = "ext:JAKES_IPHONE_PSK";
          authProtocols = [ "WPA-PSK" ];
          priority = -10;
        };
        "assuming-ungenerous-forger" = {
          pskRaw = "ext:FORGER_PSK";
          priority = -9;
        };


        "Plaza Premium Lounge".pskRaw = "ext:PLAZA_PREMIUM_PSK";
        "ANA WiFi Service" = { };
        "ASPIRE Guest" = { };
        "lfevents".pskRaw = "ext:LFEVENTS_PSK";
      };
    };

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.sway.enable = true;
    custom.games.steam.enable = true;

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
