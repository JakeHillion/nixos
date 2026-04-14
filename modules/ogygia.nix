{ pkgs, lib, config, ... }:

let
  cfg = config.custom.ogygia;

  allHosts = builtins.attrNames (builtins.readDir ../hosts);
  hosts = builtins.filter (h: h != "fanboy.cx.neb.jakehillion.me" && h != config.networking.fqdn) allHosts;

in
{
  options.custom.ogygia = {
    enable = lib.mkEnableOption "ogygia";
  };

  config = lib.mkIf cfg.enable {
    ogygia = {
      enable = true;
      domain = "neb.jakehillion.me";

      gitRemoteUrl = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";

      nebula.ipv4 = config.custom.dns.nebula.ipv4;

      irisd = {
        enable = true;
        configureNixDaemon = true;

        settings.peers.urls = builtins.map (fqdn: "http://${fqdn}:35742") hosts;
      };

      etcd = {
        enable = true;
        endpoints = config.custom.services.etcd.endpoints;
      };
    };

    environment.systemPackages = [ pkgs.ogygia ];

    nix.settings = {
      trusted-public-keys = [
        "nix-builder-boron-260125:rYsNk2FjznUnYDLjgnQJL8U+NM2XTDwK5Z9xsOTDH98="
        "nix-builder-slider-260210:A+ijnja8EoaWXElfqbo3h9y8lJbF21p717gZkAHhYQ0="
      ];
      fallback = true;
      connect-timeout = 15;
    };
  };
}
