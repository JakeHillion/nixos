{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
    ./persist.nix
  ];

  config = {
    system.stateVersion = "22.11";

    networking.hostName = "router";
    networking.domain = "home.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ## Tailscale
    age.secrets."tailscale/router.home.ts.hillion.co.uk".file = ../../secrets/tailscale/router.home.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/router.home.ts.hillion.co.uk".path;
    };

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];
  };
}
