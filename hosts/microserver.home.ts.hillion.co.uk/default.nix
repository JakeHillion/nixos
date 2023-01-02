{ config, pkgs, lib, ... }:

{
  config.system.stateVersion = "22.05";

  config.networking.hostName = "microserver";
  config.networking.domain = "home.ts.hillion.co.uk";

  imports = [
    ./hardware-configuration.nix
    ../../modules/common/default.nix
    ../../modules/rpi/rpi4.nix
  ];

  # Networking
  ## Tailscale
  config.tailscaleAdvertiseRoutes = "10.64.50.0/24,10.239.19.0/24";
  config.age.secrets."tailscale/microserver.home.ts.hillion.co.uk".file = ../../secrets/tailscale/microserver.home.ts.hillion.co.uk.age;
  config.tailscalePreAuth = config.age.secrets."tailscale/microserver.home.ts.hillion.co.uk".path;

  ## Enable IoT VLAN
  config.networking.vlans = {
    vlan2 = {
      id = 2;
      interface = "eth0";
    };
  };

  ## Enable IP forwarding for Tailscale
  config.boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
  };
}

