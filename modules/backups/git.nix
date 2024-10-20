{ config, pkgs, lib, ... }:

let
  cfg = config.custom.backups.git;
in
{
  options.custom.backups.git = {
    enable = lib.mkEnableOption "git";

    extraRepos = lib.mkOption {
      description = "A list of remotes to clone.";
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."git/git_backups_ecdsa".file = ../../secrets/git/git_backups_ecdsa.age;
    age.secrets."git/git_backups_remotes".file = ../../secrets/git/git_backups_remotes.age;
    age.secrets."git-backups/restic/128G".file = ../../secrets/restic/128G.age;

    systemd.services.backup-git = {
      description = "Git repo backup service.";

      serviceConfig = {
        DynamicUser = true;

        CacheDirectory = "backup-git";
        WorkingDirectory = "%C/backup-git";

        LoadCredential = [
          "id_ecdsa:${config.age.secrets."git/git_backups_ecdsa".path}"
          "repos_file:${config.age.secrets."git/git_backups_remotes".path}"
          "restic_password:${config.age.secrets."git-backups/restic/128G".path}"
        ];
      };

      environment = {
        GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i %d/id_ecdsa";
        RESTIC_PASSWORD_FILE = "%d/restic_password";
      };

      script = ''
        set -x
        shopt -s nullglob

        # Read and deduplicate repos
        readarray -t raw_repos < $CREDENTIALS_DIRECTORY/repos_file
        declare -A repos=(${builtins.concatStringsSep " " (builtins.map (x : "[${x}]=1") cfg.extraRepos)})
        for repo in ''${raw_repos[@]}; do repos[$repo]=1; done

        # Clean up existing repos
        declare -A dirs
        for d in *; do
          origin=$(cd $d && ${pkgs.git}/bin/git remote get-url origin)
          if ! [ -n "''${repos[$origin]}" ]; then
            echo "$origin removed from config, cleaning up..."
            rm -rf $d
          else
            dirs[$origin]=$d
          fi
        done

        # Update repos
        EXIT_CODE=0
        for repo in "''${!repos[@]}"; do
          if [ -n "''${dirs[$repo]}" ]; then
            if ! (cd ''${dirs[$repo]} && ${pkgs.git}/bin/git remote update); then EXIT_CODE=1; fi
          else
            if ! (${pkgs.git}/bin/git clone --mirror $repo); then EXIT_CODE=1; fi
          fi
        done

        # Backup to Restic
        ${pkgs.restic}/bin/restic \
          -r rest:https://restic.ts.hillion.co.uk/128G \
          --cache-dir .restic --exclude .restic \
           backup .

        if test $EXIT_CODE -ne 0; then
          echo "Some repositories failed to clone!"
          exit $EXIT_CODE
        fi
      '';
    };
    systemd.timers.backup-git = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        Persistent = true;
        OnBootSec = "10m";
        OnUnitInactiveSec = "15m";
        RandomizedDelaySec = "5m";
      };
    };
  };
}
