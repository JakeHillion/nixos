{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.11";

    networking.hostName = "router";
    networking.domain = "home.neb.jakehillion.me";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
    };

    custom.defaults = true;
    custom.impermanence.enable = true;
    custom.locations.autoServe = true;

    services.nsd.interfaces = [ "eth0" ];

    ## Interactive password
    custom.users.jake.password = true;

    ## Networking
    systemd.network = {
      enable = true;

      links = {
        "10-eth0" = {
          matchConfig.MACAddress = "20:7c:14:a1:f1:d8";
          linkConfig.Name = "eth0";
        };
        "10-eth1" = {
          matchConfig.MACAddress = "20:7c:14:a1:f1:d9";
          linkConfig.Name = "eth1";
        };
        "10-eth2" = {
          matchConfig.MACAddress = "20:7c:14:a1:f1:da";
          linkConfig.Name = "eth2";
        };
        "10-eth3" = {
          matchConfig.MACAddress = "20:7c:14:a1:f1:db";
          linkConfig.Name = "eth3";
        };
        "10-eth4" = {
          matchConfig.MACAddress = "20:7c:14:a1:f1:dc";
          linkConfig.Name = "eth4";
        };
        "10-eth5" = {
          matchConfig.MACAddress = "20:7c:14:a1:f1:dd";
          linkConfig.Name = "eth5";
        };
      };

      netdevs = {
        "10-br0" = {
          netdevConfig = {
            Kind = "bridge";
            Name = "br0";
          };
        };

        "20-vlan_iot" = {
          netdevConfig = {
            Kind = "vlan";
            Name = "iot";
          };
          vlanConfig.Id = 2;
        };
        "20-vlan_cameras" = {
          netdevConfig = {
            Kind = "vlan";
            Name = "cameras";
          };
          vlanConfig.Id = 3;
        };
      };

      networks = {
        "10-wan" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = "ipv4";
          linkConfig = {
            RequiredForOnline = "routable";
            MACAddress = "b4:fb:e4:b0:90:3c";
          };
        };

        "11-eth1" = {
          matchConfig.Name = "eth1";
          networkConfig.Bridge = "br0";
        };
        "11-eth2" = {
          matchConfig.Name = "eth2";
          networkConfig.Bridge = "br0";
        };
        "11-eth3" = {
          matchConfig.Name = "eth3";
          networkConfig.Bridge = "br0";
        };
        "11-eth4" = {
          matchConfig.Name = "eth4";
          networkConfig.Bridge = "br0";
        };
        "11-eth5" = {
          matchConfig.Name = "eth5";
          networkConfig.Bridge = "br0";
        };

        "21-lan" = {
          matchConfig.Name = "br0";
          networkConfig.Address = "10.64.50.1/24";

          vlan = [
            "iot"
            "cameras"
          ];
        };
        "22-iot" = {
          matchConfig.Name = "iot";
          networkConfig.Address = "10.239.19.1/24";
        };
        "23-cameras" = {
          matchConfig.Name = "cameras";
          networkConfig.Address = "10.133.145.1/24";
        };
      };
    };
    services.resolved.enable = lib.mkForce false;

    networking = {
      useDHCP = lib.mkForce false;
      firewall.enable = lib.mkForce false;
      nat.enable = lib.mkForce false;

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
                "tailscale0",
                "neb.jh",
              } counter accept

              ip protocol icmp counter accept comment "accept all ICMP types"

              tcp dport    22 counter accept comment "SSH"
              udp dport  4242 counter accept comment "Nebula Lighthouse"

              iifname { "br0", "iot" } udp dport 53 counter accept comment "Unbound"

              iifname br0 tcp dport 5201 counter accept comment "iperf3"

              iifname "eth0" tcp dport    53 counter accept comment "Public DNS"
              iifname "eth0" udp dport    53 counter accept comment "Public DNS"

              iifname {
                "eth0",
                "br0",
                "iot",
                "cameras",
              } ct state { established, related } counter accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;

              iifname {
                "br0",
                "iot",
                "tailscale0",
              } oifname {
                "eth0",
              } counter accept comment "Allow Internet enabled LANs to WAN"

              iifname {
                "eth0",
              } oifname {
                "br0",
                "iot",
                "tailscale0",
              } ct state { established,related } counter accept comment "Allow established back to Internet enabled LANs"

              iifname "tailscale0" oifname { "br0", "iot" } counter accept comment "Allow LAN access from Tailscale"
              iifname { "br0", "iot" } oifname "tailscale0" ct state { established,related } counter accept comment "Allow established back to Tailscale"

              ip daddr 10.64.50.21 tcp dport  7654 counter accept comment "Tang"
              ip daddr 10.64.50.27 tcp dport 32400 counter accept comment "Plex"
            }
          }

          table ip nat {
            chain prerouting {
              type nat hook prerouting priority filter; policy accept;

              iifname eth0 tcp dport  7654 counter dnat to 10.64.50.21
              iifname eth0 tcp dport 32400 counter dnat to 10.64.50.27

              iifname br0 ip daddr 185.240.111.53 udp dport 4242 dnat to 10.64.50.1
            }

            chain postrouting {
              type nat hook postrouting priority filter; policy accept;

              oifname "eth0" masquerade

              iifname tailscale0 oifname br0 snat to 10.64.50.1
              iifname tailscale0 oifname iot  snat to 10.239.19.1
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
              interfaces = [ "br0" "iot" "cameras" ];
            };
            lease-database = {
              type = "memfile";
              persist = true;
              name = "/var/lib/kea/dhcp4.leases";
            };

            option-def = [
              {
                name = "cookie";
                space = "vendor-encapsulated-options-space";
                code = 1;
                type = "string";
                array = false;
              }
            ];
            client-classes = [
              {
                name = "APC";
                test = "option[vendor-class-identifier].text == 'APC'";
                option-data = [
                  {
                    always-send = true;
                    name = "vendor-encapsulated-options";
                  }
                  {
                    name = "cookie";
                    space = "vendor-encapsulated-options-space";
                    code = 1;
                    data = "1APC";
                  }
                ];
              }
            ];

            subnet4 = [
              {
                id = 1;
                subnet = "10.64.50.0/24";
                interface = "br0";
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
                    data = "10.64.50.1, 1.1.1.1, 8.8.8.8";
                  }
                ];
                reservations = lib.lists.remove null (lib.lists.imap0
                  (i: el: if el == null then null else {
                    ip-address = "10.64.50.${toString (20 + i)}";
                    inherit (el) hw-address hostname;
                  }) [
                  null
                  null
                  { hostname = "theon"; hw-address = "00:1e:06:49:06:1e"; }
                  { hostname = "server-switch"; hw-address = "84:d8:1b:9d:0d:85"; }
                  { hostname = "apc-ap7921"; hw-address = "00:c0:b7:6b:f4:34"; }
                  { hostname = "sodium"; hw-address = "d8:3a:dd:c3:d6:2b"; }
                  { hostname = "gendry"; hw-address = "18:c0:4d:35:60:1e"; }
                  { hostname = "phoenix"; hw-address = "a8:b8:e0:04:17:a5"; }
                  { hostname = "merlin"; hw-address = "b0:41:6f:13:20:14"; }
                  { hostname = "stinger"; hw-address = "7c:83:34:be:30:dd"; }
                ]);
              }
              {
                id = 2;
                subnet = "10.239.19.0/24";
                interface = "iot";
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
                    data = "10.239.19.1, 1.1.1.1, 8.8.8.8";
                  }
                ];
                reservations = [
                  {
                    hw-address = "40:22:d8:e0:1d:50";
                    ip-address = "10.239.19.2";
                    hostname = "bedroom-everything-presence-one";
                  }
                  {
                    hw-address = "40:22:d8:e0:0f:78";
                    ip-address = "10.239.19.3";
                    hostname = "living-room-everything-presence-one";
                  }
                  {
                    hw-address = "a0:7d:9c:b0:f0:14";
                    ip-address = "10.239.19.4";
                    hostname = "hallway-wall-tablet";
                  }
                  {
                    hw-address = "d8:3a:dd:c3:d6:2b";
                    ip-address = "10.239.19.5";
                    hostname = "sodium";
                  }
                  {
                    hw-address = "48:da:35:6f:f2:4b";
                    ip-address = "10.239.19.6";
                    hostname = "hammer";
                  }
                  {
                    hw-address = "48:da:35:6f:83:b8";
                    ip-address = "10.239.19.7";
                    hostname = "charlie";
                  }
                ];
              }
              {
                id = 3;
                subnet = "10.133.145.0/24";
                interface = "cameras";
                pools = [{
                  pool = "10.133.145.64 - 10.133.145.254";
                }];
                option-data = [
                  {
                    name = "routers";
                    data = "10.133.145.1";
                  }
                  {
                    name = "broadcast-address";
                    data = "10.133.145.255";
                  }
                  {
                    name = "domain-name-servers";
                    data = "1.1.1.1, 8.8.8.8";
                  }
                ];
                reservations = [
                ];
              }
            ];
          };
        };
      };

      unbound = {
        enable = true;

        settings = {
          server = {
            interface = [
              "127.0.0.1"
              "10.64.50.1"
              "10.239.19.1"
            ];
            access-control = [
              "10.64.50.0/24 allow"
              "10.239.19.0/24 allow"
            ];
          };

          forward-zone = [
            {
              name = ".";
              forward-tls-upstream = "yes";
              forward-addr = [
                "1.1.1.1#cloudflare-dns.com"
                "1.0.0.1#cloudflare-dns.com"
                "8.8.8.8#dns.google"
                "8.8.4.4#dns.google"
              ];
            }
          ];
        };
      };
    };

    ## Tailscale
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      extraSetFlags = [
        "--advertise-routes"
        "10.64.50.0/24,10.239.19.0/24,10.133.145.0/24"
        "--advertise-exit-node"
        "--netfilter-mode=off"
      ];
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
      virtualHosts = {
        "graphs.router.home.neb.jakehillion.me" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
            }
            reverse_proxy unix///run/netdata/netdata.sock
          '';
        };
        "hammer.kvm.neb.jakehillion.me" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.6
          '';
        };
        "charlie.kvm.neb.jakehillion.me" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.7
          '';
        };
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
