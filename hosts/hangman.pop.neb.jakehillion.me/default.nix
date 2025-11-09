{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-vul-vhp-1c-1gb
  ];

  config = {
    system.stateVersion = "25.05";

    # Enable defaults and auto-serve
    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.auto_updater.allowReboot = true;

    # Tang/Clevis configuration for disk encryption
    custom.tang.enable = true;

    # WireGuard VPN Server
    networking.wireguard.interfaces."wg0" = {
      ips = [ "10.188.151.1/24" ];
      listenPort = 21372;
      privateKeyFile = "/data/wireguard/wg0-private";
      generatePrivateKeyFile = true;
      peers = [
        {
          publicKey = "16vCVIC95WmDsqMi0gb/EwoU0pA3z/kx81ZFd0ngRW4=";
          allowedIPs = [ "10.188.151.2/32" ];
        }
      ];
    };

    # Ensure WireGuard directory exists on persistent storage
    systemd.tmpfiles.rules = [
      "d /data/wireguard 0700 root root -"
    ];

    # Enable IP forwarding for routing
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
    };

    # Networking with nftables firewall
    networking.firewall.enable = lib.mkForce false;
    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet filter {
          chain output {
            type filter hook output priority 100; policy accept;
          }

          chain input {
            type filter hook input priority filter; policy drop;

            # Allow all loopback traffic
            iifname "lo" counter accept

            # Allow Nebula network
            iifname "neb.jh" counter accept

            # Allow ICMP
            ip protocol icmp counter accept comment "accept all ICMP types"

            # Allow established connections
            ct state { established, related } counter accept

            # Allow SSH
            tcp dport 22 counter accept comment "SSH"

            # Allow WireGuard
            udp dport 21372 counter accept comment "WireGuard"

            # Drop everything else
            counter drop
          }

          chain forward {
            type filter hook forward priority filter; policy drop;

            # Allow WireGuard to WAN only (blocks access to Nebula and local networks)
            iifname "wg0" oifname "enp1s0" counter accept comment "WireGuard to WAN only"

            # Allow established connections back to WireGuard
            iifname "enp1s0" oifname "wg0" ct state { established, related } counter accept comment "WAN to WireGuard established"
          }
        }

        table ip nat {
          chain postrouting {
            type nat hook postrouting priority filter; policy accept;

            # WireGuard NAT masquerading
            iifname "wg0" masquerade comment "WireGuard NAT"
          }
        }
      '';
    };
  };
}
