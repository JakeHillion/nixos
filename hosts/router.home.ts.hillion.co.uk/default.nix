{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
    ./persist.nix
  ];

  config = {
    system.stateVersion = "22.11";

    networking.hostName = "router";
    networking.domain = "home.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
    };

    ## Networking
    networking = {
      firewall.enable = lib.mkForce false;
      nat.enable = lib.mkForce false;

      useDHCP = false;
      interfaces = {
        enp1s0 = {
          name = "eth0";
          macAddress = "b4:fb:e4:b0:90:3c";
          useDHCP = true;
        };
        enp2s0 = {
          name = "eth1";
          ipv4.addresses = [
            {
              address = "10.64.50.1";
              prefixLength = 24;
            }
          ];
        };
        enp3s0 = {
          name = "eth2";
          ipv4.addresses = [
            {
              address = "10.239.19.1";
              prefixLength = 24;
            }
          ];
        };
        enp4s0 = { name = "eth3"; };
        enp5s0 = { name = "eth4"; };
        enp6s0 = { name = "eth5"; };
      };

      nftables = {
        enable = true;
        ruleset = ''
          table inet filter {
            chain output {
              type filter hook output priority 100; policy accept;
            }

            chain input {
              type filter hook input priority filter; policy drop;

              # Allow trusted networks to access the router
              iifname {
                "eth1",
                "eth2",
                "tailscale0",
              } counter accept

              ip protocol icmp counter accept comment "accept all ICMP types"

              iifname "eth0" ct state { established, related } counter accept
              iifname "eth0" drop
            }

            chain forward {
              type filter hook forward priority filter; policy drop;

              iifname {
                "eth1",
                "eth2",
              } oifname {
                "eth0",
              } counter accept comment "Allow trusted LAN to WAN"

              iifname {
                "eth0",
              } oifname {
                "eth1",
                "eth2",
              } ct state established,related counter accept comment "Allow established back to LANs"
            }
          }

          table ip nat {
            chain prerouting {
              type nat hook output priority filter; policy accept;
            }

            chain postrouting {
              type nat hook postrouting priority filter; policy accept;
              oifname "eth0" masquerade
            }
          }
        '';
      };
    };

    services = {
      dhcpd4 = {
        enable = true;
        interfaces = [ "eth1" "eth2" ];
        extraConfig = ''
          subnet 10.64.50.0 netmask 255.255.255.0 {
            interface eth1;

            option broadcast-address 10.64.50.255;
            option routers 10.64.50.1;
            range 10.64.50.64 10.64.50.254;

            option domain-name-servers 1.1.1.1, 8.8.8.8;
          }

          subnet 10.239.19.0 netmask 255.255.255.0 {
            interface eth2;

            option broadcast-address 10.239.19.255;
            option routers 10.239.19.1;
            range 10.239.19.64 10.239.19.254;

            option domain-name-servers 1.1.1.1, 8.8.8.8;
          }
        '';
        machines = [
          {
            # Zigbee Bridge
            ethernetAddress = "48:3f:da:2a:86:7a";
            ipAddress = "10.239.19.40";
            hostName = "tasmota-2A867A-1658";
          }
        ];
      };
    };

    ## Tailscale
    age.secrets."tailscale/router.home.ts.hillion.co.uk".file = ../../secrets/tailscale/router.home.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/router.home.ts.hillion.co.uk".path;
    };

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
  };
}
