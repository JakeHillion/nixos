{ config, pkgs, lib, ... }:

let
  zpool_name = "practical-defiant-coffee";
in
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "24.05";

    networking.hostId = "4d7241e9";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "zfs.zfs_arc_max=34359738368"

      # for tang - no idea why this is needed
      "ip=dhcp"

      "ixgbe.allow_unsupported_sfp=1"
    ];
    boot.extraModprobeConfig = ''
      options ixgbe allow_unsupported_sfp=1
    '';

    boot.kernelPatches = [{
      name = "ixgbe_fet10g";
      patch = ../../patches/kernel/ixgbe_fet10g.patch;
    }];

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.impermanence.enable = true;

    custom.tang = {
      enable = true;
      networkingModule = "ixgbe";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" ];
    };

    custom.users.jake.password = true; # TODO: remove me once booting has stabilised

    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Filesystems
    boot.kernelPackages = if pkgs.linuxPackages.kernelAtLeast "6.12" then pkgs.linuxPackages else pkgs.linuxPackages_6_12;

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs = {
      forceImportRoot = false;
      extraPools = [ zpool_name ];
    };

    # Remove network-online.target dependency from ZFS import to break systemd ordering cycle.
    # The ZFS encryption key is stored on the LUKS-encrypted /data filesystem (unlocked via Tang
    # in initramfs), so no network is needed for ZFS import.
    systemd.services."zfs-import-${zpool_name}" = {
      unitConfig.Wants = lib.mkForce "systemd-udev-settle.service";
    };

    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # All filesystems includes the BTRFS parts of all the hard drives. This
      # would take forever and is redundant as they get fully read regularly.
      fileSystems = [ "/data" ];
    };
    services.zfs.autoScrub = {
      enable = true;
      interval = "Wed, 02:00";
    };

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/${zpool_name}/users/jake/sync";

      backups.enable = true;
    };

    ## Chia
    age.secrets."chia/farmer.key" = {
      file = ../../secrets/chia/farmer.key.age;
      owner = "chia";
      group = "chia";
    };
    custom.chia = {
      enable = true;
      keyFile = config.age.secrets."chia/farmer.key".path;
      plotDirectories = builtins.genList (i: "/mnt/d${toString i}/plots/contract-k32") 8;
    };

    ## Journal Remote
    services.journald.remote.output = "/${zpool_name}/logs/journal/";

    ## Restic
    custom.services.restic.path = "/${zpool_name}/backups/restic";

    ## Backups
    ### Git
    custom.backups.git = {
      enable = true;
      extraRepos = [ "https://gitea.hillion.co.uk/JakeHillion/nixos.git" ];
    };

    ## Git Sync
    custom.services.git-sync.enable = true;

    ## Downloads
    custom.services.downloads = {
      metadataPath = "/${zpool_name}/downloads/metadata";
      downloadCachePath = "/${zpool_name}/downloads/torrents";
      filmsPath = "/${zpool_name}/media/films";
      tvPath = "/${zpool_name}/media/tv";
    };
    systemd.services."container@downloads".after = [ "zfs-mount.service" ];
    systemd.services."container@downloads".requires = [ "zfs-mount.service" ];

    ## Wallpapers
    custom.www.nebula = {
      enable = true;
      virtualHosts."wallpapers.${config.ogygia.domain}".extraConfig = ''
        root * /${zpool_name}/media/wallpapers
        file_server
      '';
    };

    age.secrets."restic/wallpapers/b52".rekeyFile = ../../secrets/restic/b52.age;
    services.restic.backups."wallpapers" = {
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/b52";
      passwordFile = config.age.secrets."restic/wallpapers/b52".path;
      paths = [ "/${zpool_name}/media/wallpapers" ];
    };

    ## Plex
    users.users.plex.extraGroups = [ "mediaaccess" ];
    services.plex = {
      enable = true;
      package = if lib.versionAtLeast pkgs.plexRaw.version "1.41.2" then pkgs.plex else pkgs.unstable.plex;
    };

    ## Jellyfin
    users.users.jellyfin.extraGroups = [ "mediaaccess" ];

    ## Immich
    services.immich.mediaLocation = "/${zpool_name}/media/photos";

    ## Frigate
    systemd.services."container@frigate".after = [ "zfs-mount.service" ];
    systemd.services."container@frigate".requires = [ "zfs-mount.service" ];

    ## Networking
    networking.useDHCP = lib.mkForce false;
    systemd.network = {
      # TODO: the enabled systemd-resolved breaks `hostname -f`
      enable = true;

      links = {
        "10-eth0" = {
          matchConfig.MACAddress = "a8:b8:e0:04:17:a5";
          linkConfig.Name = "eth0";
        };
        "10-eth1" = {
          matchConfig.MACAddress = "a8:b8:e0:04:17:a6";
          linkConfig.Name = "eth1";
        };
        "10-eth2" = {
          matchConfig.MACAddress = "a8:b8:e0:04:17:a7";
          linkConfig.Name = "eth2";
        };
        "10-eth3" = {
          matchConfig.MACAddress = "a8:b8:e0:04:17:a8";
          linkConfig.Name = "eth3";
        };

        "10-sfp0" = {
          matchConfig.MACAddress = "f8:f2:1e:1e:b5:74";
          linkConfig.Name = "sfp0";
        };
        "10-sfp1" = {
          matchConfig.MACAddress = "f8:f2:1e:1e:b5:75";
          linkConfig.Name = "sfp1";
        };
      };

      netdevs = {
        "20-vlan_cameras" = {
          netdevConfig = {
            Kind = "vlan";
            Name = "cameras";
          };
          vlanConfig.Id = 3;
        };
      };

      networks = {
        "10-lan" = {
          matchConfig.Name = "sfp0";
          networkConfig.DHCP = "ipv4";
          linkConfig.RequiredForOnline = "routable";

          vlan = [ "cameras" ];
        };

        "11-cameras" = {
          matchConfig.Name = "cameras";
          networkConfig.DHCP = "ipv4";
          linkConfig.RequiredForOnline = "routable";

          dhcpV4Config = {
            UseGateway = false;
            UseDNS = false;
          };
        };
      };
    };

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        sfp0 = {
          allowedTCPPorts = lib.mkForce [
            32400 # Plex
          ];
          allowedUDPPorts = lib.mkForce [ ];
        };
      };
    };
  };
}
