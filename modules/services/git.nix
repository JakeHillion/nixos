{ config, lib, ... }:

let
  cfg = config.custom.services.git;
in
{
  options.custom.services.git = {
    enable = lib.mkEnableOption "git service (gitolite)";

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
      description = "Enable backups to restic";
    };

  };

  config = lib.mkIf cfg.enable {
    services.gitolite.dataDir = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "${config.custom.impermanence.base}/services/git");

    systemd.tmpfiles.rules = lib.mkIf config.custom.impermanence.enable [
      "d ${config.custom.impermanence.base}/services/git 0755 ${config.services.gitolite.user} ${config.services.gitolite.group} - -"
    ];

    users.users.git.uid = lib.mkForce config.ids.uids.git;
    users.groups.git.gid = lib.mkForce config.ids.gids.git;

    services.gitolite = {
      enable = true;
      user = "git";
      group = "git";
      adminPubkey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOe6YuPo5/FsWaOWR4JHVrF9XQkeT4JE7TUici5ELQK/3/ngTL64JdRnVsf91piLQGyNRI3z2h18qGHQG+z55Zo= jake@merlin";
      extraGitoliteRc = ''
        push @{$RC{ENABLE}}, 'symbolic-ref';
      '';
    };

    age.secrets."backups/git/restic/mig29" = lib.mkIf cfg.backup {
      rekeyFile = ../../secrets/restic/mig29.age;
      owner = config.services.gitolite.user;
      group = config.services.gitolite.group;
    };

    services.restic.backups."git" = lib.mkIf cfg.backup {
      user = config.services.gitolite.user;
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/git/restic/mig29".path;
      paths = [
        "${config.services.gitolite.dataDir}/repositories"
      ];
      timerConfig = {
        OnBootSec = "15m";
        OnUnitInactiveSec = "10m";
        RandomizedDelaySec = "5m";
      };
    };
  };
}
