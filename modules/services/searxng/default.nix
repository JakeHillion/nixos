{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.searxng;
in
{
  options.custom.services.searxng = {
    enable = lib.mkEnableOption "searxng";
  };

  config = lib.mkIf cfg.enable {
    services.searx = {
      enable = true;
      package = pkgs.searxng;
      settings.server.bind_address = "127.0.0.1";
      settings.server.port = 8274;
      settings.server.secret_key = "$SEARXNG_SECRET_KEY";
      settings.search.formats = [ "html" "json" ];
      environmentFile = config.age.secrets."searxng/searxng-env".path;
    };

    age.secrets."searxng/searxng-env".rekeyFile = ./searxng-env.age;

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [
      "/var/lib/searx"
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."searxng.${config.ogygia.domain}" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString config.services.searx.settings.server.port}
        '';
      };
    };
  };
}
