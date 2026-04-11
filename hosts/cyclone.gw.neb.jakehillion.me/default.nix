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

    ## VLAN 5 for Cellular backup WAN
    networking.vlans = {
      wan2 = {
        id = 5;
        interface = "enp1s0f0";
      };
    };

    ## Use the network topology abstraction
    custom.router = {
      auto = true;
      extraWanInterfaces = [ "wan2" ];
      extraNatLoopbackIps = [ ];
      extraForwardRules = ''
        # WireGuard VPN forwarding rules
        iifname "wg0" oifname @wan_interfaces accept comment "WireGuard to WAN"
        iifname @wan_interfaces oifname "wg0" ct state related,established accept comment "WAN to WireGuard established"

        # Allow LAN to reach fanboy Nebula port
        iifname "enp1s0f0" oifname "openclaw" ip daddr 10.116.242.2 udp dport 4242 counter accept comment "LAN to fanboy Nebula"
        iifname "openclaw" oifname "enp1s0f0" ct state { established, related } counter accept comment "Established back from openclaw"
      '';
      extraNatRules = ''
        # WireGuard NAT masquerading
        iifname "wg0" oifname @wan_interfaces masquerade comment "WireGuard NAT"
      '';
    };

    ## WAN Failover - switches to cellular when primary is down
    custom.services.wan-failover = {
      enable = true;
      primaryInterface = "enp2s0";
      secondaryInterface = "wan2";
      primaryMetric = 100;
      secondaryMetric = 200;
      # Placeholder - update with actual command to query GL.iNet router
      secondaryIpCommand = null;
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
