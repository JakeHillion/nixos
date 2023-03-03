{ config, pkgs, lib, ... }:

{
  config.system.stateVersion = "22.05";

  config.networking.hostName = "microserver";
  config.networking.domain = "parents.ts.hillion.co.uk";

  imports = [
    ./hardware-configuration.nix
    ../../modules/common/default.nix
    ../../modules/rpi/rpi4.nix
  ];

  # Networking
  ## Tailscale
  config.tailscaleAdvertiseRoutes = "192.168.1.0/24";
  config.age.secrets."tailscale/microserver.parents.ts.hillion.co.uk".file = ../../secrets/tailscale/microserver.parents.ts.hillion.co.uk.age;
  config.tailscalePreAuth = config.age.secrets."tailscale/microserver.parents.ts.hillion.co.uk".path;

  ## Enable IP forwarding for Tailscale
  config.boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
  };
}

