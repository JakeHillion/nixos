{ config, pkgs, lib, ... }:

{
  system.stateVersion = "22.05";

  networking.hostName = "microserver";
  networking.domain = "parents.ts.hillion.co.uk";

  boot.loader.grub.enable = false;
  boot.loader.raspberryPi = {
    enable = true;
    version = 4;
  };

  imports = [
    ./hardware-configuration.nix
    ../../modules/common/default.nix
    ../../modules/secrets/tailscale/microserver.parents.ts.hillion.co.uk.nix
  ];

  tailscaleAdvertiseRoutes = "10.0.0.0/24";

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
  };
}

