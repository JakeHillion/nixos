{ config, pkgs, lib, ... }:

{
  config.system.stateVersion = "22.05";

  config.networking.hostName = "gendry";
  config.networking.domain = "jakehillion-terminals.ts.hillion.co.uk";

  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
    ./persist.nix
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
}

