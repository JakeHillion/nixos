{ config, lib, ... }:

{
  imports = [
    ./attic.nix
    ./authoritative_dns.nix
    ./downloads
    ./frigate.nix
    ./git.nix
    ./git-sync.nix
    ./gitea
    ./hearthd
    ./homeassistant
    ./homebox.nix
    ./protonmail-bridge.nix
    ./immich.nix
    ./jellyfin.nix
    ./mastodon
    ./matrix
    ./mosquitto.nix
    ./nix-builder
    ./offline-youtube
    ./ollama.nix
    ./privatebin.nix
    ./radicale.nix
    ./renovate
    ./restic
    ./status.nix
    ./tang.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
    ./zookeeper.nix
  ];
}
