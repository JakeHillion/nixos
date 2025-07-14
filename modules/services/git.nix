{ config, lib, ... }:

let
  cfg = config.custom.services.git;
in
{
  options.custom.services.git = {
    enable = lib.mkEnableOption "git service (gitolite)";
  };

  config = lib.mkIf cfg.enable {
    # Set up impermanence for git data
    services.gitolite.dataDir = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "${config.custom.impermanence.base}/services/git");

    # Create git data directory with proper permissions
    systemd.tmpfiles.rules = lib.mkIf config.custom.impermanence.enable [
      "d ${config.custom.impermanence.base}/services/git 0755 ${config.services.gitolite.user} ${config.services.gitolite.group} - -"
    ];

    # User and group configuration with static IDs
    users.users.git.uid = lib.mkForce config.ids.uids.git;
    users.groups.git.gid = lib.mkForce config.ids.gids.git;

    # Gitolite configuration
    services.gitolite = {
      enable = true;
      user = "git";
      group = "git";
      adminPubkey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOe6YuPo5/FsWaOWR4JHVrF9XQkeT4JE7TUici5ELQK/3/ngTL64JdRnVsf91piLQGyNRI3z2h18qGHQG+z55Zo= jake@merlin";
    };

  };
}
