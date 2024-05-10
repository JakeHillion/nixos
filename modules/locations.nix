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
            "boron.cx.ts.hillion.co.uk"
            "jorah.cx.ts.hillion.co.uk"
          ];
          downloads = "tywin.storage.ts.hillion.co.uk";
          gitea = "jorah.cx.ts.hillion.co.uk";
          homeassistant = "microserver.home.ts.hillion.co.uk";
          mastodon = "";
          matrix = "jorah.cx.ts.hillion.co.uk";
          tang = [
            "li.pop.ts.hillion.co.uk"
            "microserver.home.ts.hillion.co.uk"
          ];
          unifi = "jorah.cx.ts.hillion.co.uk";
          version_tracker = [ "boron.cx.ts.hillion.co.uk" "jorah.cx.ts.hillion.co.uk" ];
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
