{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.ollama;
in
{
  options.custom.services.ollama = {
    enable = lib.mkEnableOption "ollama";

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ollama";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.ollama.uid = config.ids.uids.ollama;
    users.groups.ollama.gid = config.ids.gids.ollama;

    systemd.tmpfiles.rules = [ "d ${cfg.dataPath} 0700 ollama ollama - -" ];

    services.ollama = {
      enable = true;
      home = cfg.dataPath;
      host = "[::]"; # not clear why this is necessary when reverse proxied

      user = "ollama";
      group = "ollama";

      # TODO: This downloads models with `ollama pull` but doesn't delete them when removed. This should be fixed.
      loadModels = [
        "phi4:14b"
        "deepseek-r1:32b"
      ];
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."ollama.neb.jakehillion.me".extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString config.services.ollama.port}
      '';
    };
  };
}
