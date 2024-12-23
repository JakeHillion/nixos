{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.tang;
in
{
  options.custom.services.tang = {
    enable = lib.mkEnableOption "tang";
  };

  config = lib.mkIf cfg.enable {
    services.tang = {
      enable = true;
      ipAddressAllow = [
        "138.201.252.214/32"
        "10.64.50.26/32"
        "10.64.50.27/32"
        "10.64.50.28/32"
        "10.64.50.29/32"
      ];
    };
  };
}
