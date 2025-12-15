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
    custom.router = {
      auto = true;
      extraForwardRules = ''
        # WireGuard VPN forwarding rules
        iifname "wg0" oifname "enp2s0" accept comment "WireGuard to WAN"
        iifname "enp2s0" oifname "wg0" ct state related,established accept comment "WAN to WireGuard established"
      '';
      extraNatRules = ''
        # WireGuard NAT masquerading
        iifname "wg0" oifname "enp2s0" masquerade comment "WireGuard NAT"
      '';
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

    ## Netdata
    services.netdata = {
      enable = true;
      config = {
        web = {
          "bind to" = "unix:/run/netdata/netdata.sock";
        };
      };
    };
    users.users.caddy.extraGroups = [ "netdata" ];

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
      '';
    };

    # Disable systemd-timesyncd since we're using chrony
    services.timesyncd.enable = false;

    ## Web services and KVM reverse proxies
    services.caddy = {
      enable = true;
      virtualHosts = {
        "jellyfin.jakehillion.me".extraConfig = ''
          reverse_proxy http://${config.custom.locations.locations.services.jellyfin}:8096
        '';

        "graphs.cyclone.gw.${config.ogygia.domain}" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
            }
            reverse_proxy unix///run/netdata/netdata.sock
          '';
        };
        "argus.kvm.${config.ogygia.domain}" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.12
          '';
        };
        "hammer.kvm.${config.ogygia.domain}" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.6
          '';
        };
        "charlie.kvm.${config.ogygia.domain}" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.7
          '';
        };
        "kvm.phoenix.st.${config.ogygia.domain}" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.9
          '';
        };
      };
    };
    ### HACK: Allow Caddy to restart if it fails. This happens because Nebula
    ### is too late at starting. Upstream nixos caddy does restart on failure
    ### but it's prevented on exit code 1. Set the exit code to 0 (non-failure)
    ### to override this.
    ### TODO: unclear if this is needed with Nebula but it was with Tailscale. If
    ### it is needed this should be centralised.
    systemd.services.caddy = {
      requires = [ "nebula@jakehillion.service" ];
      after = [ "nebula@jakehillion.service" ];
      serviceConfig = {
        RestartPreventExitStatus = lib.mkForce 0;
      };
    };
  };
}
