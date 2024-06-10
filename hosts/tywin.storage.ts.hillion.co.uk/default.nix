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

    ## Backups
    ### Git
    age.secrets."git/git_backups_ecdsa".file = ../../secrets/git/git_backups_ecdsa.age;
    age.secrets."git/git_backups_remotes".file = ../../secrets/git/git_backups_remotes.age;
    custom.backups.git = {
      enable = true;
      sshKey = config.age.secrets."git/git_backups_ecdsa".path;
      reposFile = config.age.secrets."git/git_backups_remotes".path;
      repos = [ "https://gitea.hillion.co.uk/JakeHillion/nixos.git" ];
    };

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
      repository = "rest:http://restic.tywin.storage.ts.hillion.co.uk/128G";
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

    ## Restic
    age.secrets."restic/128G.key" = {
      file = ../../secrets/restic/128G.age;
      owner = "restic";
      group = "restic";
    };
    age.secrets."restic/1.6T.key" = {
      file = ../../secrets/restic/1.6T.age;
      owner = "restic";
      group = "restic";
    };

    services.restic.server = {
      enable = true;
      appendOnly = true;
      extraFlags = [ "--no-auth" ];
      dataDir = "/data/backups/restic";
      listenAddress = "127.0.0.1:8000"; # TODO: can this be a Unix socket?
    };
    services.caddy = {
      enable = true;
      virtualHosts."http://restic.tywin.storage.ts.hillion.co.uk".extraConfig = ''
        bind ${config.custom.dns.tailscale.ipv4} ${config.custom.dns.tailscale.ipv6}
        reverse_proxy http://localhost:8000
      '';
    };
    ### HACK: Allow Caddy to restart if it fails. This happens because Tailscale
    ### is too late at starting. Upstream nixos caddy does restart on failure
    ### but it's prevented on exit code 1. Set the exit code to 0 (non-failure)
    ### to override this.
    systemd.services.caddy = {
      requires = [ "tailscaled.service" ];
      after = [ "tailscaled.service" ];
      serviceConfig = {
        RestartPreventExitStatus = lib.mkForce 0;
      };
    };

    services.restic.backups."prune-128G" = {
      repository = "/data/backups/restic/128G";
      user = "restic";
      passwordFile = config.age.secrets."restic/128G.key".path;

      timerConfig = {
        Persistent = true;
        OnCalendar = "02:30";
        RandomizedDelaySec = "1h";
      };

      pruneOpts = [
        "--keep-last 48"
        "--keep-within-hourly 7d"
        "--keep-within-daily 1m"
        "--keep-within-weekly 6m"
        "--keep-within-monthly 24m"
      ];
    };
    services.restic.backups."prune-1.6T" = {
      repository = "/data/backups/restic/1.6T";
      user = "restic";
      passwordFile = config.age.secrets."restic/1.6T.key".path;

      timerConfig = {
        Persistent = true;
        OnCalendar = "Wed, 02:30";
        RandomizedDelaySec = "4h";
      };

      pruneOpts = [
        "--keep-within-daily 14d"
        "--keep-within-weekly 2m"
        "--keep-within-monthly 18m"
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
      plotDirectories = builtins.genList (i: "/mnt/d${toString i}/plots/contract-k32") 7;
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
      80 # Caddy (restic.tywin.storage.ts.)
    ];
  };
}
