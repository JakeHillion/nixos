{ config, lib, ... }:

{
  imports = [
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
    ./ollama.nix
    ./privatebin.nix
    ./restic.nix
    ./tang.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
  ];
}
