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

    custom.locations.autoServe = true;

    ## Tailscale
    age.secrets."tailscale/tywin.storage.ts.hillion.co.uk".file = ../../secrets/tailscale/tywin.storage.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/tywin.storage.ts.hillion.co.uk".path;
      ipv4Addr = "100.115.31.91";
      ipv6Addr = "fd7a:115c:a1e0:ab12:4843:cd96:6273:1f5b";
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
        bind ${config.custom.tailscale.ipv4Addr} ${config.custom.tailscale.ipv6Addr}
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

    ## Firewall
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      80 # Caddy (restic.tywin.storage.ts.)
      14002 # Storj Dashboard (d0.)
      14003 # Storj Dashboard (d1.)
      14004 # Storj Dashboard (d2.)
      14005 # Storj Dashboard (d3.)
    ];
  };
}
