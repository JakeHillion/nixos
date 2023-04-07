{ pkgs, lib, config, ... }:

let
  cfg = config.custom.www.www-repo;
in
{
  options.custom.www.www-repo = {
    enable = lib.mkEnableOption "www-repo";

    location = lib.mkOption {
      default = "/var/www";
      type = lib.types.path;
      description = "Location of the local www repository.";
    };

    remote = lib.mkOption {
      default = "https://gitea.hillion.co.uk/JakeHillion/www.git";
      type = lib.types.str;
      description = "Remote to pull from for the www repository.";
    };

    branch = lib.mkOption {
      default = "main";
      type = lib.types.str;
      description = "Branch to pull from the remote.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/www 0755 ${config.services.caddy.user} ${config.services.caddy.group} - -"
    ];

    systemd.timers.clone-www-repo = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitInactiveSec = "60m";
        Unit = "clone-www-repo.service";
      };
    };

    systemd.services.clone-www-repo = {
      description = "Clone and pull the www repo";

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "${config.services.caddy.user}";
        Group = "${config.services.caddy.group}";
      };

      script = ''
        if [ ! -d "${cfg.path}/.git" ] ; then
            ${pkgs.git}/bin/git clone ${cfg.remote} ${cfg.path}
        else
            cd ${cfg.path}
            ${pkgs.git} remote set-url origin ${cfg.remote}
            ${pkgs.git}/bin/git fetch
            ${pkgs.git}/bin/git reset --hard origin/${cfg.branch}
        fi
      '';
    };
  };
}

