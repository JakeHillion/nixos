{ config, lib, ... }:

{
  imports = [
    ./downloads.nix
    ./gitea/default.nix
    ./homeassistant.nix
    ./mastodon/default.nix
    ./matrix.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
  ];
}
