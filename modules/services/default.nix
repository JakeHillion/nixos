{ config, lib, ... }:

{
  imports = [
    ./attic.nix
    ./authoritative_dns.nix
    ./downloads.nix
    ./frigate.nix
    ./git.nix
    ./gitea/default.nix
    ./homeassistant.nix
    ./homebox.nix
    ./immich.nix
    ./isponsorblocktv.nix
    ./jellyfin.nix
    ./mastodon/default.nix
    ./matrix/default.nix
    ./mosquitto.nix
    ./ollama.nix
    ./privatebin.nix
    ./radicale.nix
    ./restic/default.nix
    ./status.nix
    ./tang.nix
    ./unifi.nix
    ./version_tracker.nix
    ./zigbee2mqtt.nix
    ./zookeeper.nix
  ];
}
