{ config, pkgs, lib, ... }:

{
  config.system.stateVersion = "22.05";

  config.networking.hostName = "gendry";
  config.networking.domain = "jakehillion-terminals.ts.hillion.co.uk";

  imports = [
    ../../modules/common/default.nix
    ../../modules/desktop/awesome/default.nix
    ../../modules/spotify/default.nix
    ./bluetooth.nix
    ./hardware-configuration.nix
    ./persist.nix
    ./resilio.nix
  ];

  config.boot.loader.systemd-boot.enable = true;
  config.boot.loader.efi.canTouchEfiVariables = true;

  ## Tailscale
  config.age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".file = ../../secrets/tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk.age;
  config.tailscalePreAuth = config.age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".path;

  ## Password (for interactive logins)
  config.age.secrets."passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake".file = ../../secrets/passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake.age;
  config.users.users."jake".passwordFile = config.age.secrets."passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake".path;

  config.security.sudo.wheelNeedsPassword = lib.mkForce true;

  ## Enable btrfs compression
  config.fileSystems."/data".options = [ "compress=zstd" ];
  config.fileSystems."/nix".options = [ "compress=zstd" ];

  ## Graphics
  config.boot.initrd.kernelModules = [ "amdgpu" ];
  config.services.xserver.videoDrivers = [ "amdgpu" ];

  ## Spotify
  config.home-manager.users.jake.services.spotifyd.settings = {
    global = {
      device_name = "Gendry";
      device_type = "computer";
      bitrate = 320;
    };
  };
}
