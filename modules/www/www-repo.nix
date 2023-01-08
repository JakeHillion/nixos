{ pkgs, lib, config, ... }:

{
  config.systemd.tmpfiles.rules = [
    "d /var/www 0755 ${config.services.caddy.user} ${config.services.caddy.group} - -"
  ];

  config.systemd.timers.clone-www-repo = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitInactiveSec = "60m";
      Unit = "clone-www-repo.service";
    };
  };

  config.systemd.services.clone-www-repo = {
    description = "Clone and pull the www repo";

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "${config.services.caddy.user}";
      Group = "${config.services.caddy.group}";
    };

    script = with pkgs; ''
      if [ ! -d "/var/www/.git" ] ; then
          ${git}/bin/git clone https://gitea.hillion.co.uk/JakeHillion/www.git /var/www
      else
          cd /var/www
          ${git}/bin/git fetch
          ${git}/bin/git reset --hard origin/main
      fi
    '';
  };
}

