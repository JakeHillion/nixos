{ config, lib, ... }:

{
  imports = [
    ./attic.nix
    ./authoritative_dns.nix
    ./downloads.nix
    ./frigate.nix
    ./git.nix
    ./git-sync.nix
    ./gitea
    ./homeassistant
    ./homebox.nix
    ./protonmail-bridge.nix
    ./immich.nix
    ./jellyfin.nix
    ./mastodon
    ./matrix
    ./mosquitto.nix
    ./nix-builder
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
