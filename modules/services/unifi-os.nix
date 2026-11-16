{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.unifi-os;
  vmCfg = config.custom.vms.instances.unifi-os;
in
{
  options.custom.services.unifi-os = {
    enable = lib.mkEnableOption "UniFi OS Server VM";
  };

  config = lib.mkIf cfg.enable {
    # UniFi OS Server itself is installed by hand inside the VM and keeps
    # itself updated. cloud-init only prepares the base system.
    custom.vms.instances.unifi-os = {
      index = 1;
      vcpus = 4;
      memoryMiB = 8 * 1024;
      diskSize = "64G";
      baseImage = pkgs.fetchurl {
        url = "https://cloud.debian.org/images/cloud/trixie/20261103-2651/debian-13-genericcloud-amd64-20261103-2651.qcow2";
        sha512 = "d25999de0770d4cde1be72c299ba3ad94eac7ea8fd4d18f8cc86c69df69337e2e8a91d64465a9bfd8f2a78c566fcbcb0842eacc91c09efdef72d719d9f13b535";
      };

      shares = [ "backup" ];

      firewall = {
        allowedTCPPorts = [
          22 # SSH
          8080 # device inform
        ];
        allowedUDPPorts = [
          3478 # STUN
        ];
      };
      # unifi.hillion.co.uk's AAAA is the VM's address, so the host's Caddy
      # answers the web ports there as it does on the host's own IPv4.
      hostPorts = {
        tcp = [ 80 443 ];
        udp = [ 443 ];
      };
      forwardPorts = [
        { proto = "tcp"; port = 8080; }
        { proto = "udp"; port = 3478; }
      ];

      cloudConfig = {
        users = [{
          name = config.custom.user;
          shell = "/bin/bash";
          sudo = "ALL=(ALL) NOPASSWD:ALL";
          lock_passwd = true;
          ssh_authorized_keys = config.users.users.${config.custom.user}.openssh.authorizedKeys.keys;
        }];
        ssh_pwauth = false;

        package_update = true;
        package_upgrade = true;
        packages = [
          "qemu-guest-agent"
          "unattended-upgrades"
          "podman"
          "slirp4netns"
        ];

        write_files = [
          {
            path = "/etc/apt/apt.conf.d/20auto-upgrades";
            content = ''
              APT::Periodic::Update-Package-Lists "1";
              APT::Periodic::Unattended-Upgrade "1";
            '';
          }
          {
            path = "/etc/apt/apt.conf.d/52unattended-upgrades-local";
            content = ''
              Unattended-Upgrade::Automatic-Reboot "true";
              Unattended-Upgrade::Automatic-Reboot-Time "04:00";
            '';
          }
        ];

        runcmd = [
          [ "systemctl" "start" "qemu-guest-agent" ]
        ];
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts."unifi.hillion.co.uk".extraConfig = ''
        reverse_proxy https://${vmCfg.ipv4Address}:11443 {
          header_up Host {host}
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."unifi-os.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy https://${vmCfg.ipv4Address}:11443 {
          header_up Host {host}
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    };

    age.secrets."backups/unifi-os/restic/mig29" = {
      rekeyFile = ../../secrets/restic/mig29.age;
    };

    services.restic.backups."unifi-os" = {
      user = "root";
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/unifi-os/restic/mig29".path;
      paths = lib.attrValues vmCfg.sharePaths;
    };
  };
}
