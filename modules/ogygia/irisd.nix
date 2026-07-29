{ pkgs, lib, config, ... }:

let
  cfg = config.custom.ogygia;

  allHosts = builtins.attrNames (builtins.readDir ../../hosts);
  hosts = builtins.filter (h: h != "fanboy.cx.neb.jakehillion.me" && h != config.networking.fqdn) allHosts;
in
{
  config = lib.mkIf cfg.enable {
    ogygia = {
      irisd = {
        enable = true;
        configureNixDaemon = true;

        settings.peers.urls = builtins.map (fqdn: "http://${fqdn}:35742") hosts;
      };

      nebula = {
        groups = [ "irisd-client" ];

        firewall.inbound = [
          { groups = [ "irisd-client" ]; port = 35742; proto = "tcp"; }
        ];
      };
    };

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/cache/private/ogygia-irisd" ];
  };
}
