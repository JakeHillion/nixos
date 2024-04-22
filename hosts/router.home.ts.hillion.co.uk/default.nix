{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
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

    ## Interactive password
    custom.users.jake.password = true;

    ## Impermanence
    custom.impermanence.enable = true;

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
                "lo",
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

              ip daddr 10.64.50.20 tcp dport 32400 counter accept comment "Plex"

              ip daddr 10.64.50.20 tcp dport 8444 counter accept comment "Chia"

              ip daddr 10.64.50.21 tcp dport 7654 counter accept comment "Tang"
            }
          }

          table ip nat {
            chain prerouting {
              type nat hook prerouting priority filter; policy accept;

              iifname eth0 tcp dport 32400 counter dnat to 10.64.50.20

              iifname eth0 tcp dport 8444 counter dnat to 10.64.50.20

              iifname eth0 tcp dport 7654 counter dnat to 10.64.50.21
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
      kea = {
        dhcp4 = {
          enable = true;

          settings = {
            interfaces-config = {
              interfaces = [ "eth1" "eth2" ];
            };
            lease-database = {
              type = "memfile";
              persist = false;
            };
            subnet4 = [
              {
                subnet = "10.64.50.0/24";
                interface = "eth1";
                pools = [{
                  pool = "10.64.50.64 - 10.64.50.254";
                }];
                option-data = [
                  {
                    name = "routers";
                    data = "10.64.50.1";
                  }
                  {
                    name = "broadcast-address";
                    data = "10.64.50.255";
                  }
                  {
                    name = "domain-name-servers";
                    data = "1.1.1.1, 8.8.8.8";
                  }
                ];
                reservations = [
                  {
                    # tywin.storage.ts.hillion.co.uk
                    hw-address = "c8:7f:54:6d:e1:03";
                    ip-address = "10.64.50.20";
                    hostname = "tywin";
                  }
                  {
                    # syncbox
                    hw-address = "00:1e:06:49:06:1e";
                    ip-address = "10.64.50.22";
                    hostname = "syncbox";
                  }
                  {
                    # microserver.home.ts.hillion.co.uk
                    hw-address = "e4:5f:01:b4:58:95";
                    ip-address = "10.64.50.21";
                    hostname = "microserver";
                  }
                ];
              }
              {
                subnet = "10.239.19.0/24";
                interface = "eth2";
                pools = [{
                  pool = "10.239.19.64 - 10.239.19.254";
                }];
                option-data = [
                  {
                    name = "routers";
                    data = "10.239.19.1";
                  }
                  {
                    name = "broadcast-address";
                    data = "10.239.19.255";
                  }
                  {
                    name = "domain-name-servers";
                    data = "1.1.1.1, 8.8.8.8";
                  }
                ];
                reservations = [
                  {
                    # bedroom-everything-presence-one
                    hw-address = "40:22:d8:e0:1d:50";
                    ip-address = "10.239.19.2";
                    hostname = "bedroom-everything-presence-one";
                  }
                  {
                    # living-room-everything-presence-one
                    hw-address = "40:22:d8:e0:0f:78";
                    ip-address = "10.239.19.3";
                    hostname = "living-room-everything-presence-one";
                  }
                ];
              }
            ];
          };
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/router.home.ts.hillion.co.uk".file = ../../secrets/tailscale/router.home.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/router.home.ts.hillion.co.uk".path;
      ipv4Addr = "100.105.71.48";
      ipv6Addr = "fd7a:115c:a1e0:ab12:4843:cd96:6269:4730";
    };

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;

    ## Zigbee2Mqtt
    custom.services.zigbee2mqtt.enable = true;

    ## Netdata
    services.netdata = {
      enable = true;
      config = {
        web = {
          "bind to" = "unix:/run/netdata/netdata.sock";
        };
      };
    };
    services.caddy = {
      enable = true;
      virtualHosts."http://graphs.router.home.ts.hillion.co.uk" = {
        listenAddresses = [ config.custom.tailscale.ipv4Addr config.custom.tailscale.ipv6Addr ];
        extraConfig = "reverse_proxy unix///run/netdata/netdata.sock";
      };
    };
    users.users.caddy.extraGroups = [ "netdata" ];
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
  };
}
