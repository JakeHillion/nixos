{ config, pkgs, lib, ... }:

let
  cfg = config.custom.backups.git;
in
{
  options.custom.backups.git = {
    enable = lib.mkEnableOption "git";

    repos = lib.mkOption {
      description = "A list of remotes to clone.";
      type = with lib.types; listOf str;
      default = [ ];
    };
    reposFile = lib.mkOption {
      description = "A file containing the remotes to clone, one per line.";
      type = with lib.types; nullOr str;
      default = null;
    };
    sshKey = lib.mkOption {
      description = "SSH private key to use when cloning repositories over SSH.";
      type = with lib.types; nullOr str;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."git-backups/restic/128G".file = ../../secrets/restic/128G.age;

    systemd.services.backup-git = {
      description = "Git repo backup service.";

      serviceConfig = {
        DynamicUser = true;

        CacheDirectory = "backup-git";
        WorkingDirectory = "%C/backup-git";

        LoadCredential = [
          "restic_password:${config.age.secrets."git-backups/restic/128G".path}"
        ] ++ (if cfg.sshKey == null then [ ] else [ "id_ecdsa:${cfg.sshKey}" ])
        ++ (if cfg.reposFile == null then [ ] else [ "repos_file:${cfg.reposFile}" ]);
      };

      environment = {
        GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i %d/id_ecdsa";
        RESTIC_PASSWORD_FILE = "%d/restic_password";
      };

      script = ''
        shopt -s nullglob

        # Read and deduplicate repos
        ${if cfg.reposFile == null then "" else "readarray -t raw_repos < $CREDENTIALS_DIRECTORY/repos_file"}
        declare -A repos=(${builtins.concatStringsSep " " (builtins.map (x : "[${x}]=1") cfg.repos)})
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
        OnUnitInactiveSec = "15m";
        RandomizedDelaySec = "5m";
        Unit = "backup-git.service";
      };
    };
  };
}
