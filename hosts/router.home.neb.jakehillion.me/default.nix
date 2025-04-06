{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.11";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;
    custom.impermanence.enable = true;
    custom.locations.autoServe = true;

    services.nsd.interfaces = [ "eth0" ];

    ## Interactive password
    custom.users.jake.password = true;

    ## Networking
    networking = {
      useDHCP = false;

      interfaces = {
        enp1s0 = {
          name = "eth0";
          useDHCP = true;
        };
        enp2s0 = { name = "eth1"; };
        enp3s0 = { name = "eth2"; };
        enp4s0 = { name = "eth3"; };
        enp5s0 = { name = "eth4"; };
        enp6s0 = { name = "eth5"; };
      };
    };

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;

    ## Zigbee2Mqtt
    custom.services.zigbee2mqtt.enable = true;

    ## Netdata
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
        "kvm.gendry.jakehillion-terminals.neb.jakehillion.me" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
            }
            reverse_proxy http://10.239.19.9
          '';
        };
      };
    };
    users.users.caddy.extraGroups = [ "netdata" ];
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
