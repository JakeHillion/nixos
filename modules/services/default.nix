{ config, lib, ... }:

{
  imports = [
    ./downloads.nix
    ./gitea.nix
    ./homeassistant.nix
    ./mastodon/default.nix
    ./matrix.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
  ];
}
