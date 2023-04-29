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
          matrix = "vm.strangervm.ts.hillion.co.uk";
        };
      };
    };
  };

  config = lib.mkIf cfg.autoServe {
    custom.services.matrix.enable = cfg.locations.services.matrix == config.networking.fqdn;
  };
}
