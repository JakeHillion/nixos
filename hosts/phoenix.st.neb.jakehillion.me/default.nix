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

    networking.hostName = "phoenix";
    networking.domain = "st.neb.jakehillion.me";
    networking.hostId = "4d7241e9";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "ip=dhcp"
      "zfs.zfs_arc_max=34359738368"

      # zswap
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];
    boot.initrd = {
      availableKernelModules = [ "igc" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices = {
          "disk0-crypt".secretFile = "/data/disk_encryption.jwe";
          "disk1-crypt".secretFile = "/data/disk_encryption.jwe";
        };
      };
    };

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.impermanence.enable = true;

    custom.users.jake.password = true; # TODO: remove me once booting has stabilised

    ## Filesystems
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs = {
      forceImportRoot = false;
      extraPools = [ zpool_name ];
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

    ## Resilio
    custom.resilio = {
      enable = false;
      backups.enable = true;

      folders =
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
    };
    services.resilio.directoryRoot = "/${zpool_name}/sync";

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

    ## Restic
    custom.services.restic.path = "/${zpool_name}/backups/restic";

    ## Backups
    ### Git
    custom.backups.git = {
      enable = true;
      extraRepos = [ "https://gitea.hillion.co.uk/JakeHillion/nixos.git" ];
    };

    ## Downloads
    custom.services.downloads = {
      metadataPath = "/${zpool_name}/downloads/metadata";
      downloadCachePath = "/${zpool_name}/downloads/torrents";
      filmsPath = "/${zpool_name}/media/films";
      tvPath = "/${zpool_name}/media/tv";
    };

    ## Wallpapers
    services.caddy = {
      enable = true;

      virtualHosts."wallpapers.neb.jakehillion.me" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          tls {
            ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
          }

          root * /${zpool_name}/media/wallpapers
          file_server
        '';
      };
    };

    age.secrets."restic/wallpapers/1.6T".file = ../../secrets/restic/1.6T.age;
    services.restic.backups."wallpapers" = {
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.neb.jakehillion.me/1.6T";
      passwordFile = config.age.secrets."restic/wallpapers/1.6T".path;
      paths = [ "/${zpool_name}/media/wallpapers" ];
    };

    ## Plex
    users.users.plex.extraGroups = [ "mediaaccess" ];
    services.plex.enable = true;

    ## Immich
    services.immich.mediaLocation = "/${zpool_name}/media/photos";

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
          matchConfig.Name = "eth0";
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
      trustedInterfaces = [ "tailscale0" "neb.jh" ];
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        eth0 = {
          allowedTCPPorts = lib.mkForce [
            32400 # Plex
          ];
          allowedUDPPorts = lib.mkForce [ ];
        };
      };
    };

    ## Tailscale
    services.tailscale.enable = true;
  };
}
