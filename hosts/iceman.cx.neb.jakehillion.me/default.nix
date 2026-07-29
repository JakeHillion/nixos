{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-hetzner-ax162-r
  ];

  config = {
    system.stateVersion = "25.11";

    custom.defaults = true;

    # iceman's Nebula keypair hasn't been grabbed yet, so it can't join the
    # ogygia-managed overlay on the first deploy. Ship with Nebula disabled,
    # then gather its pubkey, add ogygia.nebula.groups + pubKey, sign with
    # `ogygia nebula rekey`, and drop this override. Nebula IP 172.20.0.27 is
    # reserved in modules/dns.nix.
    ogygia.nebula.enable = lib.mkForce false;

    custom.tang.enable = true;

    ## Networking (Hetzner dedicated server: static addressing, no DHCP)
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
    };

    networking = {
      useDHCP = false;
      interfaces.eth0 = {
        ipv4.addresses = [{
          address = "37.27.136.99";
          prefixLength = 26;
        }];
        ipv6.addresses = [{
          address = "2a01:4f9:3100:1048::2";
          prefixLength = 64;
        }];
      };
      defaultGateway = {
        address = "37.27.136.65";
        interface = "eth0";
      };
      defaultGateway6 = {
        address = "fe80::1";
        interface = "eth0";
      };
    };
  };
}
