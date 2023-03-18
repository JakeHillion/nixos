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
      default = {
        services = {
          downloads = "tywin.storage.ts.hillion.co.uk";
          mastodon = "vm.strangervm.ts.hillion.co.uk";
          matrix = "vm.strangervm.ts.hillion.co.uk";
        };
      };
    };
  };

  config = lib.mkIf cfg.autoServe {
    custom.services.downloads.enable = cfg.locations.services.downloads == config.networking.fqdn;
    custom.services.mastodon.enable = cfg.locations.services.mastodon == config.networking.fqdn;
    custom.services.matrix.enable = cfg.locations.services.matrix == config.networking.fqdn;
  };
}
