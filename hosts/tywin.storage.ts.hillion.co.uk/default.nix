{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.11";

    networking.hostName = "tywin";
    networking.domain = "storage.ts.hillion.co.uk";
    networking.hostId = "2a9b6df5";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ## Tailscale
    age.secrets."tailscale/tywin.storage.ts.hillion.co.uk".file = ../../secrets/tailscale/tywin.storage.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/tywin.storage.ts.hillion.co.uk".path;
    };

    ## Filesystems
    fileSystems."/".options = [ "compress=zstd" ];

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs = {
      forceImportRoot = false;
      extraPools = [ "data" ];
    };
    boot.kernelParams = [ "zfs.zfs_arc_max=25769803776" ];

    services.zfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
    };
    services.sanoid.enable = true;

    fileSystems."/mnt/d0".options = [ "x-systemd.mount-timeout=3m" ];

    ## Resilio
    custom.resilio.enable = true;

    services.resilio.deviceName = "tywin.storage";
    services.resilio.directoryRoot = "/data/users/jake/sync";
    services.resilio.storagePath = "/data/users/jake/sync/.sync";

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

    ## Chia
    age.secrets."chia/farmer.key" = {
      file = ../../secrets/chia/farmer.key.age;
      owner = "chia";
      group = "chia";
    };
    custom.chia = {
      enable = true;
      openFirewall = true;
      path = "/data/chia";
      keyFile = config.age.secrets."chia/farmer.key".path;
      targetAddress = "xch1tl87mjd9zpugs7qy2ysc3j4qlftqlyjn037jywq6v2y4kp22g74qahn6sw";
      plotDirectories = [
        "/mnt/d0/plots/contract-k32"
      ];
    };
    services.sanoid.datasets."data/chia" = {
      autosnap = true;
      autoprune = true;

      hourly = 0;
      daily = 7;
      weekly = 12;
      monthly = 6;
    };

    ## Storj
    age.secrets."storj/zfs_auth" = {
      file = ../../secrets/storj/tywin/zfs_auth.age;
      owner = "storj";
      group = "storj";
    };
    custom.storj = {
      enable = true;
      openFirewall = true;
      email = "jake+storj@hillion.co.uk";
      wallet = "0x03cebe2608945D51f0bcE6c5ef70b4948fCEcfEe";
    };

    custom.storj.instances =
      let
        mkStorj = index: {
          name = "d${toString index}";
          value = {
            configDir = "/mnt/d${toString index}/storj/config";
            identityDir = "/mnt/d${toString index}/storj/identity";

            serverPort = 28967 + 1 + index;
            externalAddress = "d${toString index}.tywin.storj.hillion.co.uk:${toString (28967 + 1 + index)}";
            consoleAddress = "100.115.31.91:${toString (14002 + 1 + index)}";

            storage = "1000GB";
          };
        };
        instances = builtins.genList (x: x) 1;
      in
      builtins.listToAttrs (builtins.map mkStorj instances) // {
        zfs = {
          configDir = "/data/storj/config";
          identityDir = "/data/storj/identity";
          storage = "500GB";
          consoleAddress = "100.115.31.91:14002";
          serverPort = 28967;
          externalAddress = "zfs.tywin.storj.hillion.co.uk:28967";
          authorizationTokenFile = config.age.secrets."storj/zfs_auth".path;
        };
      };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 14002 14003 ];
  };
}
