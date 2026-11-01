{ config, pkgs, lib, ... }:

let
  wan = config.custom.networking.topology.home.wanInterface;
in
{
  imports = [
    ../../models/t0-topton-1u-10g
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.tang = {
      enable = true;
      # WAN is on an SFP+ port
      networkingModule = lib.mkForce "ixgbe";
    };

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        sjbhqAOvEFiMWEBTIc/6mb8BlDE4n/lQF8tM78IZWFo=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Interactive password
    custom.users.jake.password = true;

    ## Use the network topology abstraction
    custom.networking.router = {
      auto = true;
      extraForwardRules = ''
        # WireGuard VPN forwarding rules
        iifname "wg0" oifname "${wan}" accept comment "WireGuard to WAN"
        iifname "${wan}" oifname "wg0" ct state related,established accept comment "WAN to WireGuard established"

        # Allow LAN to reach fanboy Nebula port
        iifname "lan" oifname "openclaw" ip daddr 10.116.242.2 udp dport 4242 counter accept comment "LAN to fanboy Nebula"
        iifname "openclaw" oifname "lan" ct state { established, related } counter accept comment "Established back from openclaw"

        # Cellular failover: internet-enabled networks out, established back
        iifname { "lan", "iot", "openclaw" } oifname "cellular" counter accept comment "LAN to cellular failover"
        iifname "cellular" oifname { "lan", "iot", "openclaw" } ct state { established, related } counter accept comment "Cellular to LAN established"
        iifname "wg0" oifname "cellular" counter accept comment "WireGuard to cellular failover"
        iifname "cellular" oifname "wg0" ct state { established, related } counter accept comment "Cellular to WireGuard established"

        # Olilo: IPv6 only, stateful
        meta nfproto ipv6 oifname "olilo" tcp flags syn tcp option maxseg size set rt mtu comment "Clamp MSS to tunnel MTU"
        meta nfproto ipv6 iifname "olilo" tcp flags syn tcp option maxseg size set rt mtu comment "Clamp MSS to tunnel MTU"
        meta nfproto ipv6 iifname "lan" oifname "olilo" counter accept comment "LAN to Olilo IPv6"
        meta nfproto ipv6 iifname "olilo" oifname "lan" ct state { established, related } counter accept comment "Olilo IPv6 to LAN established"
      '';
      extraInputRules = ''
        # Olilo: ICMPv6 (NDP, PMTU) and DHCPv6-PD replies
        meta nfproto ipv6 iifname "olilo" meta l4proto ipv6-icmp counter accept comment "Olilo ICMPv6"
        meta nfproto ipv6 iifname "olilo" udp sport 547 udp dport 546 counter accept comment "Olilo DHCPv6 client"
      '';
      extraNatRules = ''
        # WireGuard NAT masquerading
        iifname "wg0" oifname "${wan}" masquerade comment "WireGuard NAT"

        # Cellular failover NAT masquerading
        oifname "cellular" masquerade comment "Cellular NAT"
      '';
    };

    ## Fail over to cellular when the primary WAN stops reaching the internet
    custom.networking.wanFailover = {
      enable = true;
      primaryInterface = wan;
      backup = {
        interface = "cellular";
        gateway = "10.69.186.1";
      };
    };

    ## Olilo L2TP: IPv6 uplink. IPv4 on the session is never routed.
    age.secrets."olilo-l2tp-password".rekeyFile = ./olilo-l2tp-password.age;

    custom.networking.l2tp = {
      enable = true;
      server = "l2tp.olilo.co.uk";
      username = "jake.hillion@olilo.l2tp";
      passwordFile = config.age.secrets."olilo-l2tp-password".path;
      ifname = "olilo";
      delegatedPrefix = "2a11:2646:14b6::/48";
    };

    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

    ## Cellular VLAN on SFP+ port (high metric so primary WAN stays default)
    networking.vlans.cellular = {
      id = 5;
      interface = "enp1s0f0";
    };
    networking.interfaces.cellular = {
      ipv4.addresses = [{
        address = "10.69.186.2";
        prefixLength = 24;
      }];
      ipv4.routes = [{
        address = "0.0.0.0";
        prefixLength = 0;
        via = "10.69.186.1";
        options.metric = "2048";
      }];
    };

    ## WireGuard VPN Server
    networking.wireguard.interfaces."wg0" = {
      ips = [ "10.200.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = "/data/wireguard/wg0-private";
      generatePrivateKeyFile = true;
      peers = [
        {
          publicKey = "AeCCmn+x3wEGCTMBtkfe17G+nJ7enOgvbWoj+a3lZQA=";
          allowedIPs = [ "10.200.0.2/32" ];
        }
        {
          publicKey = "3o/j1cK0ltpEYMU7rLE7DudN+ZAwSlL8FyxAUeF58W4=";
          allowedIPs = [ "10.200.0.3/32" ];
        }
      ];
    };

    # Ensure WireGuard directory exists on persistent storage
    systemd.tmpfiles.rules = [
      "d /data/wireguard 0700 root root -"
    ];

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;

    ## NTP server
    services.chrony = {
      enable = true;
      servers = [
        "10.239.19.5"
        "pool.ntp.org"
      ];
      extraConfig = ''
        # Allow clients from local networks
        allow 10.64.50.0/24
        allow 10.239.19.0/24
        allow 10.133.145.0/24
        allow 10.116.242.0/24
      '';
    };

    # Disable systemd-timesyncd since we're using chrony
    services.timesyncd.enable = false;

    ## IPv6: SLAAC with a global /64 from the Olilo /48 on LAN, ULA on IoT
    networking.interfaces.lan.ipv6.addresses = [{
      address = "2a11:2646:14b6:1::1";
      prefixLength = 64;
    }];
    networking.interfaces.iot.ipv6.addresses = [{
      address = "fd57:5aa6:c07e::1";
      prefixLength = 64;
    }];

    services.radvd = {
      enable = true;
      config = ''
        interface lan {
          AdvSendAdvert on;
          AdvManagedFlag off;
          AdvOtherConfigFlag off;
          prefix 2a11:2646:14b6:1::/64 {
            AdvOnLink on;
            AdvAutonomous on;
            AdvRouterAddr on;
          };
        };
        interface iot {
          AdvSendAdvert on;
          AdvManagedFlag off;
          AdvOtherConfigFlag off;
          AdvDefaultLifetime 0;
          prefix fd57:5aa6:c07e::/64 {
            AdvOnLink on;
            AdvAutonomous on;
            AdvRouterAddr on;
          };
        };
      '';
    };

    ## Knot DNS - public listen address
    services.knot.settings.server.listen = [
      "185.240.111.53@53"
    ];

    ## Unbound: forwarding resolver for LAN clients. Forwards everything to
    ## Cloudflare/Google over DoT, and serves a local `unifi` record so UniFi
    ## devices adopt to the controller on boron.
    services.unbound = {
      enable = true;
      # Serve LAN clients only; leave the host's own resolver untouched.
      resolveLocalQueries = false;
      settings = {
        server = {
          interface = [ "127.0.0.1" "::1" "10.64.50.1" ];
          access-control = [
            "127.0.0.0/8 allow"
            "::1 allow"
            "10.64.50.0/24 allow"
          ];
          # Bind the LAN address even if it isn't up yet at start.
          ip-freebind = true;
          tls-cert-bundle = "/etc/ssl/certs/ca-certificates.crt";
          hide-identity = true;
          hide-version = true;

          # Refresh popular records (and their DNSSEC keys) in the background
          # before they expire, so hot lookups stay cache hits.
          prefetch = true;
          prefetch-key = true;

          # UniFi devices look up the bare hostname `unifi`; point it at the
          # controller's public name so there's no hardcoded IP here. `redirect`
          # (not `transparent`) makes unbound resolve the CNAME target to an
          # address rather than returning a dangling CNAME.
          local-zone = [ ''"unifi." redirect'' ];
          local-data = [ ''"unifi. 3600 IN CNAME unifi.hillion.co.uk."'' ];
        };
        forward-zone = [{
          name = ".";
          forward-tls-upstream = true;
          forward-addr = [
            "1.1.1.1@853#cloudflare-dns.com"
            "1.0.0.1@853#cloudflare-dns.com"
            "8.8.8.8@853#dns.google"
            "8.8.4.4@853#dns.google"
          ];
        }];
      };
    };

    ## Web services and KVM reverse proxies
    services.caddy = {
      enable = true;
      virtualHosts."jellyfin.jakehillion.me".extraConfig = ''
        reverse_proxy http://${config.custom.locations.locations.services.jellyfin}:8096
      '';
      virtualHosts."homeassistant.hillion.co.uk".extraConfig = ''
        reverse_proxy http://${config.custom.locations.locations.services.homeassistant}:8123
      '';
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts = {
        "argus.kvm.${config.ogygia.domain}".extraConfig = ''
          reverse_proxy http://10.239.19.12
        '';
        "hammer.kvm.${config.ogygia.domain}".extraConfig = ''
          reverse_proxy http://10.239.19.6
        '';
        "charlie.kvm.${config.ogygia.domain}".extraConfig = ''
          reverse_proxy http://10.239.19.7
        '';
        "kvm.phoenix.st.${config.ogygia.domain}".extraConfig = ''
          reverse_proxy http://10.239.19.9
        '';
      };
    };
  };
}
