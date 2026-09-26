{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.tang;

  servedGroups = lib.lists.filter
    (g: lib.attrsets.hasAttr config.networking.fqdn g.pins)
    (lib.attrsets.attrValues config.custom.tang.fleet.groups);
in
{
  options.custom.services.tang = {
    enable = lib.mkEnableOption "tang";
  };

  config = lib.mkIf cfg.enable {
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/tang" ];

    services.tang = {
      enable = true;
      ipAddressAllow = [ "127.0.0.0/8" ] ++ lib.lists.unique (lib.lists.concatMap (g: g.sources) servedGroups);
    };

    networking.firewall.allowedTCPPorts = [ 7654 ];
  };
}
