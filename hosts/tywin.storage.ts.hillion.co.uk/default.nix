{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.11";

    networking.hostName = "tywin";
    networking.domain = "storage.ts.hillion.co.uk";
    networking.hostId = "2a9b6df5";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "ip=dhcp"
      "zfs.zfs_arc_max=25769803776"
    ];
    boot.initrd = {
      availableKernelModules = [ "r8169" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices."root".secretFile = "/disk_encryption.jwe";
      };
    };

    custom.locations.autoServe = true;
    custom.defaults = true;

    # zram swap: used in the hope it will give the ZFS ARC more room to back off
    zramSwap = {
      enable = true;
      memoryPercent = 200;
      algorithm = "zstd";
    };

    ## Tailscale
    age.secrets."tailscale/tywin.storage.ts.hillion.co.uk".file = ../../secrets/tailscale/tywin.storage.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/tywin.storage.ts.hillion.co.uk".path;
    };

    ## Filesystems
    fileSystems."/".options = [ "compress=zstd" ];

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs = {
      forceImportRoot = false;
      extraPools = [ "data" ];
    };

    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # All filesystems includes the BTRFS parts of all the hard drives. This
      # would take forever and is redundant as they get fully read regularly.
      fileSystems = [ "/" ];
    };
    services.zfs.autoScrub = {
      enable = true;
      interval = "Wed, 02:00";
    };

    ## Restic
    custom.services.restic.path = "/data/backups/restic";

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

    age.secrets."resilio/restic/128G.key" = {
      file = ../../secrets/restic/128G.age;
      owner = "rslsync";
      group = "rslsync";
    };
    services.restic.backups."sync" = {
      repository = "rest:https://restic.ts.hillion.co.uk/128G";
      user = "rslsync";
      passwordFile = config.age.secrets."resilio/restic/128G.key".path;

      timerConfig = {
        Persistent = true;
        OnUnitInactiveSec = "15m";
        RandomizedDelaySec = "5m";
      };

      paths = [ "/data/users/jake/sync" ];
      exclude = [
        "/data/users/jake/sync/.sync"
        "/data/users/jake/sync/*/.sync"

        "/data/users/jake/sync/resources/media/films"
        "/data/users/jake/sync/resources/media/iso"
        "/data/users/jake/sync/resources/media/tv"

        "/data/users/jake/sync/dad/media"
      ];
    };

    ## Chia
    age.secrets."chia/farmer.key" = {
      file = ../../secrets/chia/farmer.key.age;
      owner = "chia";
      group = "chia";
    };
    custom.chia = {
      enable = true;
      openFirewall = true;
      keyFile = config.age.secrets."chia/farmer.key".path;
      plotDirectories = builtins.genList (i: "/mnt/d${toString i}/plots/contract-k32") 8;
    };

    ## Downloads
    custom.services.downloads = {
      metadataPath = "/data/downloads/metadata";
      downloadCachePath = "/data/downloads/torrents";
      filmsPath = "/data/media/films";
      tvPath = "/data/media/tv";
    };

    ## Plex
    users.users.plex.extraGroups = [ "mediaaccess" ];
    services.plex = {
      enable = true;
      openFirewall = true;
    };

    ## Networking
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      80 # Caddy HTTP  1-2 (restic.ts.)
      443 # Caddy HTTPS 1-2 (restic.ts.)
    ];
  };
}
