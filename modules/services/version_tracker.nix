{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.version_tracker;
in
{
  options.custom.services.version_tracker = {
    enable = lib.mkEnableOption "version_tracker";

    path = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/version_tracker";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.version_tracker = { };
    users.users.version_tracker = {
      home = cfg.path;
      createHome = true;
      isSystemUser = true;
      group = "version_tracker";
    };

    age.secrets."version_tracker/ssh.key" = {
      file = ../../secrets/version_tracker/ssh.key.age;
      owner = "version_tracker";
      group = "version_tracker";
    };

    systemd.services.version_tracker = {
      description = "NixOS version tracker.";

      environment = {
        GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i ${config.age.secrets."version_tracker/ssh.key".path}";
      };

      preStart = with pkgs; ''
        if ! test -d repo/.git; then
            ${git}/bin/git clone git@ssh.gitea.hillion.co.uk:JakeHillion/nixos.git repo
        fi
        cd repo
        ${git}/bin/git fetch
      '';
      script = with pkgs; ''
        PORT=30653
        cd repo

        code=0
        for path in hosts/*
        do
            hostname=''${path##*/}
            if test -f "hosts/$hostname/darwin"; then continue; fi

            if rev=$(${curl}/bin/curl -s --connect-timeout 15 http://$hostname:30653/nixos/system/configurationRevision); then
                echo "$hostname: $rev"
                if ! ${git}/bin/git tag -f "live/$hostname" $rev; then
                    echo "WARNING: $hostname points to invalid ref!"
                    continue
                fi
                ${git}/bin/git push -f origin "live/$hostname"
            else
                echo "$hostname: failed to reach"
            fi
        done
      '';

      serviceConfig = {
        User = "version_tracker";
        Group = "version_tracker";

        WorkingDirectory = cfg.path;
      };
    };
    systemd.timers.version_tracker = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitInactiveSec = "15m";
        Unit = "version_tracker.service";
      };
    };
  };
}
