{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/spotify/default.nix
    ./bluetooth.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.05";

    networking.hostName = "gendry";
    networking.domain = "jakehillion-terminals.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_rsa"
        ".ssh/id_ecdsa"
      ];
      userExtraDirs.jake = [
        ".local/share/PrismLauncher"
      ];
    };

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.awesome.enable = true;

    ## Resilio
    custom.resilio.enable = true;

    services.resilio.deviceName = "gendry.jakehillion-terminals";
    services.resilio.directoryRoot = "/data/sync";
    services.resilio.storagePath = "/data/sync/.sync";

    custom.resilio.folders =
      let
        folderNames = [
          "dad"
          "joseph"
          "projects"
          "resources"
          "sync"
        ];
        mkFolder = name: {
          name = name;
          secret = {
            name = "resilio/plain/${name}";
            file = ../../secrets/resilio/plain/${name}.age;
          };
        };
      in
      builtins.map (mkFolder) folderNames;

    ## Tailscale
    age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".file = ../../secrets/tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".path;
    };

    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Graphics
    boot.initrd.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    ## Spotify
    home-manager.users.jake.services.spotifyd.settings = {
      global = {
        device_name = "Gendry";
        device_type = "computer";
        bitrate = 320;
      };
    };

    users.users."${config.custom.user}" = {
      packages = with pkgs; [
        prismlauncher
      ];
    };

    ## Networking
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
  };
}
