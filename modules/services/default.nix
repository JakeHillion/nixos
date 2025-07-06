{ config, lib, ... }:

{
  imports = [
    ./attic.nix
    ./authoritative_dns.nix
    ./downloads.nix
    ./frigate.nix
    ./gitea/default.nix
    ./homeassistant.nix
    ./immich.nix
    ./isponsorblocktv.nix
    ./jellyfin.nix
    ./mastodon/default.nix
    ./matrix.nix
    ./mosquitto.nix
    ./ollama.nix
    ./privatebin.nix
    ./radicale.nix
    ./restic.nix
    ./status.nix
    ./tang.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
  ];
}
