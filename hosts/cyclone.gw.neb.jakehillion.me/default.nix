{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-topton-1u-10g
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.tang.enable = true;

    ## Interactive password
    custom.users.jake.password = true;

    ## Use the network topology abstraction
    custom.networking.router = {
      auto = true;
      extraForwardRules = ''
        # WireGuard VPN forwarding rules
        iifname "wg0" oifname "enp2s0" accept comment "WireGuard to WAN"
        iifname "enp2s0" oifname "wg0" ct state related,established accept comment "WAN to WireGuard established"

        # Allow LAN to reach fanboy Nebula port
        iifname "lan" oifname "openclaw" ip daddr 10.116.242.2 udp dport 4242 counter accept comment "LAN to fanboy Nebula"
        iifname "openclaw" oifname "lan" ct state { established, related } counter accept comment "Established back from openclaw"

        # Cellular failover: internet-enabled networks out, established back
        iifname { "lan", "iot", "exo", "openclaw" } oifname "cellular" counter accept comment "LAN to cellular failover"
        iifname "cellular" oifname { "lan", "iot", "exo", "openclaw" } ct state { established, related } counter accept comment "Cellular to LAN established"
        iifname "wg0" oifname "cellular" counter accept comment "WireGuard to cellular failover"
        iifname "cellular" oifname "wg0" ct state { established, related } counter accept comment "Cellular to WireGuard established"
      '';
      extraNatRules = ''
        # WireGuard NAT masquerading
        iifname "wg0" oifname "enp2s0" masquerade comment "WireGuard NAT"

        # Cellular failover NAT masquerading
        oifname "cellular" masquerade comment "Cellular NAT"
      '';
    };

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

    ## Knot DNS - public listen address
    services.knot.settings.server.listen = [
      "185.240.111.53@53"
    ];

    ## Web services and KVM reverse proxies
    services.caddy = {
      enable = true;
      virtualHosts."jellyfin.jakehillion.me".extraConfig = ''
        reverse_proxy http://${config.custom.locations.locations.services.jellyfin}:8096
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
