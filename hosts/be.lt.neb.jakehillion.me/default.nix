{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "be";
    networking.domain = "lt.neb.jakehillion.me";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_ecdsa_sk_keys"
      ];
    };

    ## WiFi
    age.secrets."wifi/be.lt.neb.jakehillion.me".file = ../../secrets/wifi/be.lt.neb.jakehillion.me.age;
    networking.wireless = {
      enable = true;
      secretsFile = config.age.secrets."wifi/be.lt.neb.jakehillion.me".path;

      networks = {
        "Hillion WPA3 Network".pskRaw = "ext:HILLION_WPA3_NETWORK_PSK";
      };
    };

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.awesome.enable = true;

    ## Tailscale
    services.tailscale.enable = true;

    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## Networking
    networking.firewall = {
      trustedInterfaces = [ "neb.jh" ];
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
        iot = {
          allowedTCPPorts = lib.mkForce [
          ];
          allowedUDPPorts = lib.mkForce [
          ];
        };
      };
    };
  };
}
