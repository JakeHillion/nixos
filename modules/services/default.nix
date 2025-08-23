{ config, lib, ... }:

{
  imports = [
    ./attic.nix
    ./authoritative_dns.nix
    ./downloads.nix
    ./frigate.nix
    ./git.nix
    ./gitea
    ./homeassistant
    ./homebox.nix
    ./immich.nix
    ./isponsorblocktv.nix
    ./jellyfin.nix
    ./mastodon
    ./matrix
    ./mosquitto.nix
    ./ollama.nix
    ./privatebin.nix
    ./radicale.nix
    ./restic
    ./status.nix
    ./tang.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
    ./zookeeper.nix
  ];
}
