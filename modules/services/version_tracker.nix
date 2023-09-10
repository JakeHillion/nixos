{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.version_tracker;
in
{
  options.custom.services.version_tracker = {
    enable = lib.mkEnableOption "version_tracker";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."version_tracker/ssh.key".file = ../../secrets/version_tracker/ssh.key.age;

    systemd.services.version_tracker = {
      description = "NixOS version tracker.";

      serviceConfig = {
        DynamicUser = true;

        CacheDirectory = "version_tracker";
        WorkingDirectory = "%C/version_tracker";

        LoadCredential = "id_ecdsa:${config.age.secrets."version_tracker/ssh.key".path}";
      };

      environment = {
        GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i %d/id_ecdsa";
      };

      script = with pkgs; ''
        PORT=30653

        if ! test -d repo/.git; then
            ${git}/bin/git clone git@ssh.gitea.hillion.co.uk:JakeHillion/nixos.git repo
        fi
        cd repo
        ${git}/bin/git fetch
        ${git}/bin/git switch --detach origin/main

        code=0
        for path in hosts/*
        do
            hostname=''${path##*/}
            if test -f "hosts/$hostname/darwin"; then continue; fi

            if rev=$(${curl}/bin/curl -s --connect-timeout 15 http://$hostname:30653/current/nixos/system/configurationRevision); then
                echo "$hostname: $rev (current)"
                if ${git}/bin/git tag -f "current/$hostname" "$rev"; then
                    ${git}/bin/git push -f origin "current/$hostname"
                else
                    echo "WARNING: $hostname points to invalid ref!"
                fi
            else
                echo "$hostname: failed to reach"
            fi

            if rev=$(${curl}/bin/curl -s --connect-timeout 15 http://$hostname:30653/booted/nixos/system/configurationRevision); then
                echo "$hostname: $rev (booted)"
                if ${git}/bin/git tag -f "booted/$hostname" "$rev"; then
                    ${git}/bin/git push -f origin "booted/$hostname"
                else
                    echo "WARNING: $hostname points to invalid ref!"
                fi
                
            else
                echo "$hostname: failed to reach"
            fi
        done
      '';
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
