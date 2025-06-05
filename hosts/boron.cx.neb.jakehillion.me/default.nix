{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;
    boot.kernelParams =
      let
        ifcfg = builtins.head config.networking.interfaces.enp6s0.ipv4.addresses;
      in
      [ "ip=${ifcfg.address}::${config.networking.defaultGateway.address}:255.255.255.192:${config.networking.hostName}:eth0:none" ];
    custom.tang = {
      enable = true;
      networkingModule = "igb";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" ];
    };

    ## Kernel
    ### Explicitly use the latest kernel at time of writing because the LTS
    ### kernels available in NixOS do not seem to support this server's very
    ### modern hardware.
    ### custom.sched_ext.enable implies >=6.12, if this is removed the kernel may need to be pinned again. >=6.10 seems good.
    custom.sched_ext.enable = true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Impermanence
    custom.impermanence = {
      enable = true;
      cache.enable = true;

      userExtraFiles.jake = [
        ".ssh/id_ecdsa"
        ".ssh/id_rsa"
      ];
    };
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      btrfs subvolume delete /cache/system
      btrfs subvolume snapshot /cache/empty_snapshot /cache/system

      btrfs subvolume delete /cache/nix-builds
      btrfs subvolume snapshot /cache/empty_snapshot /cache/nix-builds
      chmod 0700 /cache/nix-builds
    '';
    nix = {
      settings = {
        build-dir = "/cache/nix-builds/";
      };
    };

    ## Custom Services
    custom = {
      locations.autoServe = true;
      www.global.enable = true;
      services = {
        gitea.actions = {
          enable = true;
          tokenSecret = ../../modules/services/gitea/actions/boron.age;
          capacity = 4;
          dockerMemoryHigh = 8 * 1024 * 1024 * 1024; # 8 GiB
        };
        matrix.mautrix_discord = true;
        zookeeper.enable = true;
      };
    };

    # TODO: make this a group instead of a single host
    services.nebula.networks.jakehillion.firewall.inbound = [
      { host = "fanboy.cx"; port = "8553"; proto = "tcp"; }
    ];

    services.knot.settings.server.listen = [
      "138.201.252.214@53"
      "2a01:4f8:173:23d2::2@53"
    ];

    ## Filesystems
    services.btrfs.autoScrub = {
      enable = true;
      interval = "Tue, 02:00";
      # By default both /data and /nix would be scrubbed. They are the same filesystem so this is wasteful.
      fileSystems = [ "/data" ];
    };

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## General usability
    ### Make podman available for dev tools such as act
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
      };
    };
    users.users.jake.extraGroups = [ "podman" ];

    ## Networking
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
    };

    networking = {
      useDHCP = false;

      interfaces = {
        enp6s0 = {
          name = "eth0";
          ipv4.addresses = [
            {
              address = "138.201.252.208";
              prefixLength = 32;
            }
            {
              address = "138.201.252.214";
              prefixLength = 26;
            }
          ];
          ipv6.addresses = [{
            address = "2a01:4f8:173:23d2::2";
            prefixLength = 64;
          }];
        };
      };
      defaultGateway = {
        address = "138.201.252.193";
        interface = "eth0";
      };
      defaultGateway6 = {
        address = "fe80::1";
        interface = "eth0";
      };
    };

    networking.firewall.enable = lib.mkForce false;
    networking.nftables = {
      enable = true;
      ruleset = ''
        ####################################
        # 1) inet filter table (always run)
        ####################################
        table inet filter {
          chain input {
            type filter hook input priority 0; policy drop;

            iifname "lo" accept
            iifname "neb.jh" accept
            ct state established,related accept

            iifname eth0 ip daddr 138.201.252.214 tcp dport 22      ct state new accept comment "SSH"
            iifname eth0 ip daddr 138.201.252.214 tcp dport 3022    ct state new accept comment "SSH (Gitea) - redirected to 22"
            iifname eth0 ip daddr 138.201.252.214 tcp dport 53      ct state new accept comment "DNS (TCP)"
            iifname eth0 ip daddr 138.201.252.214 tcp dport 80      ct state new accept comment "HTTP 1-2"
            iifname eth0 ip daddr 138.201.252.214 tcp dport 443     ct state new accept comment "HTTPS 1-2"
            iifname eth0 ip daddr 138.201.252.214 tcp dport 7654    ct state new accept comment "Tang"
            iifname eth0 ip daddr 138.201.252.214 tcp dport 8080    ct state new accept comment "Unifi (inform)"

            iifname eth0 ip daddr 138.201.252.214 udp dport 53      ct state new accept comment "DNS (UDP)"
            iifname eth0 ip daddr 138.201.252.214 udp dport 443     ct state new accept comment "HTTP 3"
            iifname eth0 ip daddr 138.201.252.214 udp dport 3478    ct state new accept comment "Unifi STUN"
            iifname eth0 ip daddr 138.201.252.214 udp dport 4242    ct state new accept comment "Nebula Lighthouse"

            ${lib.optionalString
              (config.custom.services.gitea.enable && config.custom.services.gitea.actions.enable)
              ''
                # Redirect container SSH traffic directly to the Gitea SSH port
                ip saddr 10.108.27.2 ip daddr 10.108.27.1 tcp dport ${toString config.custom.services.gitea.sshPort} accept
              ''
            }
          }
        }

        #########################################################
        # 2) nat tables (only if Gitea is enabled)
        #########################################################
        ${lib.optionalString config.custom.services.gitea.enable ''
          # IPv4 nat
          table ip nat {
            chain prerouting {
              type nat hook prerouting priority 0;

              # Redirect incoming SSH on eth0:22 -> Gitea SSH port
              iifname eth0 tcp dport 22      redirect to :${toString config.custom.services.gitea.sshPort}

              # Redirect incoming SSH on eth0:<gitea_sshPort> -> 22
              iifname eth0 tcp dport ${toString config.custom.services.gitea.sshPort} redirect to :22

              ${lib.optionalString
                config.custom.services.gitea.actions.enable
                ''
                  # Redirect container traffic: 10.108.27.2 -> 138.201.252.214:22 -> Gitea SSH port
                  ip saddr 10.108.27.2 ip daddr 138.201.252.214 tcp dport 22 redirect to :${toString config.custom.services.gitea.sshPort}
                ''
              }
            }

            chain output {
              type nat hook output priority 0;

              # Redirect locally-originating connections to 138.201.252.214:22 -> Gitea SSH port
              ip daddr 138.201.252.214 tcp dport 22 redirect to :${toString config.custom.services.gitea.sshPort}
            }
          }

          # IPv6 nat
          table ip6 nat {
            chain prerouting {
              type nat hook prerouting priority 0;

              # Redirect incoming SSH on eth0:22 -> Gitea SSH port (IPv6)
              iifname eth0 tcp dport 22      redirect to :${toString config.custom.services.gitea.sshPort}

              # Redirect incoming SSH on eth0:<gitea_sshPort> -> 22 (IPv6)
              iifname eth0 tcp dport ${toString config.custom.services.gitea.sshPort} redirect to :22
            }

            chain output {
              type nat hook output priority 0;

              # Redirect locally-originating connections to 2a01:4f8:173:23d2::2:22 -> Gitea SSH port (IPv6)
              ip6 daddr 2a01:4f8:173:23d2::2 tcp dport 22 redirect to :${toString config.custom.services.gitea.sshPort}
            }
          }
        ''
        }
      '';
    };
  };
}

