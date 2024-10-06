{ config, pkgs, lib, ... }:

{
  imports = [
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

    custom.defaults = true;

    ## Interactive password
    custom.users.jake.password = true;

    ## Impermanence
    custom.impermanence.enable = true;

    ## Networking
    networking = {
      firewall.enable = lib.mkForce false;
      nat.enable = lib.mkForce false;

      useDHCP = false;

      vlans = {
        cameras = {
          id = 3;
          interface = "eth2";
        };
      };

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
        cameras /* cameras@eth2 */ = {
          ipv4.addresses = [
            {
              address = "10.133.145.1";
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

              iifname { "eth0", "cameras" } ct state { established, related } counter accept
              iifname { "eth0", "cameras" } drop
            }

            chain forward {
              type filter hook forward priority filter; policy drop;

              iifname {
                "eth1",
                "eth2",
                "tailscale0",
              } oifname {
                "eth0",
              } counter accept comment "Allow trusted LAN to WAN"

              iifname {
                "eth0",
              } oifname {
                "eth1",
                "eth2",
                "tailscale0",
              } ct state { established,related } counter accept comment "Allow established back to LANs"

              iifname "tailscale0" oifname { "eth1", "eth2" } counter accept comment "Allow LAN access from Tailscale"
              iifname { "eth1", "eth2" } oifname "tailscale0" ct state { established,related } counter accept comment "Allow established back to Tailscale"

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

              iifname tailscale0 oifname eth1 snat to 10.64.50.1
              iifname tailscale0 oifname eth2 snat to 10.239.19.1
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
              interfaces = [ "eth1" "eth2" "cameras" ];
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
                    data = "10.64.50.1, 1.1.1.1, 8.8.8.8";
                  }
                ];
                reservations = lib.lists.imap0
                  (i: el: {
                    ip-address = "10.64.50.${toString (20 + i)}";
                    inherit (el) hw-address hostname;
                  }) [
                  { hostname = "tywin"; hw-address = "c8:7f:54:6d:e1:03"; }
                  { hostname = "microserver"; hw-address = "e4:5f:01:b4:58:95"; }
                  { hostname = "theon"; hw-address = "00:1e:06:49:06:1e"; }
                  { hostname = "server-switch"; hw-address = "84:d8:1b:9d:0d:85"; }
                  { hostname = "apc-ap7921"; hw-address = "00:c0:b7:6b:f4:34"; }
                  { hostname = "sodium"; hw-address = "d8:3a:dd:c3:d6:2b"; }
                  { hostname = "gendry"; hw-address = "18:c0:4d:35:60:1e"; }
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
                    data = "10.239.19.1, 1.1.1.1, 8.8.8.8";
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
                ];
              }
              {
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
    age.secrets."tailscale/router.home.ts.hillion.co.uk".file = ../../secrets/tailscale/router.home.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/router.home.ts.hillion.co.uk".path;
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
      virtualHosts."http://graphs.router.home.ts.hillion.co.uk" = {
        listenAddresses = [ config.custom.dns.tailscale.ipv4 config.custom.dns.tailscale.ipv6 ];
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
