{ config, pkgs, lib, ... }:

let
  cfg = config.custom.ca.consumer;
in
{
  options.custom.ca.consumer = {
    enable = lib.mkEnableOption "ca.service";
  };

  config = lib.mkIf cfg.enable {
    security.pki.certificates = [ (builtins.readFile ./cert.pem) ];
  };
}
