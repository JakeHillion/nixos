{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ../../modules/spotify/default.nix
    ./bluetooth.nix
    ./hardware-configuration.nix
    ./persist.nix
  ];

  config = {
    system.stateVersion = "22.05";

    networking.hostName = "gendry";
    networking.domain = "jakehillion-terminals.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ## Desktop
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

    ## Password (for interactive logins)
    age.secrets."passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake".file = ../../secrets/passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake.age;
    users.users."jake".passwordFile = config.age.secrets."passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake".path;

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
  };
}
