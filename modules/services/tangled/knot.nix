{ config, lib, ... }:

let
  cfg = config.custom.services.tangled_knot;
  locations = config.custom.locations.locations;
in
{
  options.custom.services.tangled_knot = {
    enable = lib.mkEnableOption "tangled knot";

    owner = lib.mkOption {
      type = lib.types.str;
      default = "did:plc:m4n4b4s6gonjbmuj2e6zrsir";
      description = "DID of the knot owner";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "knot.tangled.hillion.co.uk";
    };

    appviewEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://tangled.hillion.co.uk";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tangled.knot = {
      enable = true;

      appviewEndpoint = cfg.appviewEndpoint;

      stateDir = lib.mkIf config.custom.impermanence.enable
        "${config.custom.impermanence.base}/home/git";

      server = {
        owner = cfg.owner;
        hostname = cfg.hostname;
      };
    };

    networking.firewall.allowedTCPPorts = [
      5555
    ];
  };
}
