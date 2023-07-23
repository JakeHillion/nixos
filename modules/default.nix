{ config, lib, ... }:

{
  imports = [
    ./backups/default.nix
    ./chia.nix
    ./common/hostinfo.nix
    ./desktop/awesome/default.nix
    ./impermanence.nix
    ./locations.nix
    ./resilio.nix
    ./services/downloads.nix
    ./services/mastodon/default.nix
    ./services/matrix.nix
    ./services/version_tracker.nix
    ./services/zigbee2mqtt.nix
    ./storj.nix
    ./tailscale.nix
    ./users.nix
    ./www/global.nix
    ./www/www-repo.nix
  ];

  options.custom = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "jake";
    };
  };
}
