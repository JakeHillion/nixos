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
          authoritative_dns = [ "boron.cx.ts.hillion.co.uk" ];
          downloads = "phoenix.st.ts.hillion.co.uk";
          gitea = "boron.cx.ts.hillion.co.uk";
          homeassistant = "stinger.pop.ts.hillion.co.uk";
          mastodon = "";
          matrix = "boron.cx.ts.hillion.co.uk";
          prometheus = "boron.cx.ts.hillion.co.uk";
          restic = "phoenix.st.ts.hillion.co.uk";
          tang = [
            "li.pop.ts.hillion.co.uk"
            "microserver.home.ts.hillion.co.uk"
            "sodium.pop.ts.hillion.co.uk"
          ];
          unifi = "boron.cx.ts.hillion.co.uk";
          version_tracker = [ "boron.cx.ts.hillion.co.uk" ];
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
