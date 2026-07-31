{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-hetzner-ax162-r
  ];

  config = {
    system.stateVersion = "26.05";

    custom.defaults = true;

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        UqRL8CsYJytwXQf01N/UPGUXqgCkxdrxrjDedPmEhWQ=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    custom.tang.enable = true;

    ## Gitea Actions
    custom.services.gitea.actions-vm = {
      enable = true;
      instances = 8;
    };

    nix = {
      distributedBuilds = true;
      settings = {
        builders-use-substitutes = true;
      };
      buildMachines = [{
        hostName = "slider.pop.${config.ogygia.domain}";
        system = "aarch64-linux";
        protocol = "ssh-ng";
        maxJobs = 4;
        speedFactor = 1;
        supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
        sshUser = "nix-builder";
        sshKey = "${config.custom.impermanence.base}/system/etc/ssh/ssh_host_ed25519_key";
      }];
    };

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    networking.firewall.interfaces.eth0 = {
      allowedTCPPorts = [
        53 # DNS
      ];
      allowedUDPPorts = [
        53 # DNS
        4242 # Nebula Lighthouse
      ];
    };

    ## Authoritative DNS: serve the public zones from this host's public IPs.
    services.knot.settings.server.listen = [
      "37.27.136.99@53"
      "2a01:4f9:3100:1048::2@53"
    ];

    ## Networking (Hetzner dedicated server: static addressing, no DHCP)
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
    };

    networking = {
      useDHCP = false;
      interfaces.eth0 = {
        ipv4.addresses = [{
          address = "37.27.136.99";
          prefixLength = 26;
        }];
        ipv6.addresses = [{
          address = "2a01:4f9:3100:1048::2";
          prefixLength = 64;
        }];
      };
      defaultGateway = {
        address = "37.27.136.65";
        interface = "eth0";
      };
      defaultGateway6 = {
        address = "fe80::1";
        interface = "eth0";
      };
    };
  };
}
