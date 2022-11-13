{ config, pkgs, lib, ... }:

{
  system.stateVersion = "22.05";

  networking.hostName = "microserver";
  networking.domain = "home.ts.hillion.co.uk";

  imports = [
    ../../modules/common/default.nix
    ../../modules/secrets/tailscale/microserver.home.ts.hillion.co.uk.nix
  ];

  tailscaleAdvertiseRoutes = "10.64.50.0/24,10.239.19.0/24";

  networking.vlans = {
    vlan2 = {
      id = 2;
      interface = "eth0";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
  };
}

