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
        "10.64.50.0/24"
        "127.0.0.0/8"
        "138.201.252.214/32"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 7654 ];
  };
}
