{ config, lib, ... }:

let
  cfg = config.custom.locations;
in
{
  options.custom.locations = {
    autoServe = lib.mkOption {
      default = false;
      type = lib.types.bool;
    };

    locations = lib.mkOption {
      readOnly = true;
    };
  };

  config = lib.mkMerge [
    {
      custom.locations.locations = {
        services = {
          attic = "phoenix.st.${config.ogygia.domain}";
          authoritative_dns = [
            "boron.cx.${config.ogygia.domain}"
          ];
          downloads = "phoenix.st.${config.ogygia.domain}";
          frigate = "phoenix.st.${config.ogygia.domain}";
          git = "boron.cx.${config.ogygia.domain}";
          gitea = "boron.cx.${config.ogygia.domain}";
          hearthd = "stinger.pop.${config.ogygia.domain}";
          homeassistant = "stinger.pop.${config.ogygia.domain}";
          homebox = "boron.cx.${config.ogygia.domain}";
          immich = "phoenix.st.${config.ogygia.domain}";
          jellyfin = "phoenix.st.${config.ogygia.domain}";
          mastodon = "";
          matrix = "boron.cx.${config.ogygia.domain}";
          mautrix_discord = "warlock.cx.${config.ogygia.domain}";
          mosquitto = "stinger.pop.${config.ogygia.domain}";
          nix-builder = [
            "slider.pop.${config.ogygia.domain}"
            "boron.cx.${config.ogygia.domain}"
          ];
          offline-youtube = "phoenix.st.${config.ogygia.domain}";
          ollama = "merlin.rig.${config.ogygia.domain}";
          privatebin = "boron.cx.${config.ogygia.domain}";
          prometheus = "boron.cx.${config.ogygia.domain}";
          radicale = "boron.cx.${config.ogygia.domain}";
          renovate = "boron.cx.${config.ogygia.domain}";
          restic = "phoenix.st.${config.ogygia.domain}";
          status = "boron.cx.${config.ogygia.domain}";
          tang = [
            "boron.cx.${config.ogygia.domain}"
            "cyclone.gw.${config.ogygia.domain}"
            "li.pop.${config.ogygia.domain}"
            "stinger.pop.${config.ogygia.domain}"
            "warlock.cx.${config.ogygia.domain}"
          ];
          unifi = "boron.cx.${config.ogygia.domain}";
          version_tracker = [ "boron.cx.${config.ogygia.domain}" ];
          zigbee2mqtt = "stinger.pop.${config.ogygia.domain}";
        };
      };
    }

    (lib.mkIf cfg.autoServe
      {
        custom.services = lib.mapAttrsRecursive
          (path: value: {
            enable =
              if builtins.isList value
              then builtins.elem config.networking.fqdn value
              else config.networking.fqdn == value;
          })
          cfg.locations.services;
      })
  ];
}
