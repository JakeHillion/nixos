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
          authoritative_dns = [
            "boron.cx.neb.jakehillion.me"
            "router.home.neb.jakehillion.me"
          ];
          downloads = "phoenix.st.neb.jakehillion.me";
          frigate = "phoenix.st.neb.jakehillion.me";
          gitea = "boron.cx.neb.jakehillion.me";
          homeassistant = "stinger.pop.neb.jakehillion.me";
          immich = "phoenix.st.neb.jakehillion.me";
          inventree = "boron.cx.neb.jakehillion.me";
          mastodon = "";
          matrix = "boron.cx.neb.jakehillion.me";
          prometheus = "boron.cx.neb.jakehillion.me";
          restic = "phoenix.st.neb.jakehillion.me";
          tang = [
            "li.pop.neb.jakehillion.me"
            "sodium.pop.neb.jakehillion.me"
          ];
          unifi = "boron.cx.neb.jakehillion.me";
          version_tracker = [ "boron.cx.neb.jakehillion.me" ];
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
