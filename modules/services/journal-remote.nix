{ config, lib, ... }:

let
  cfg = config.custom.services.journal_remote;
in
{
  options.custom.services.journal_remote = {
    enable = lib.mkEnableOption "journal-remote";

    maxUse = lib.mkOption {
      type = lib.types.str;
      default = "500G";
      description = "Maximum disk space for remote journal storage.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.journald.remote = {
      enable = true;
      listen = "http";
      settings.Remote = {
        SplitMode = "host";
        MaxUse = cfg.maxUse;
        MaxFileSize = "1G";
      };
    };

    # Pin UID/GID to prevent drift on impermanence systems
    users.users.systemd-journal-remote.uid = config.ids.uids.systemd-journal-remote;
    users.groups.systemd-journal-remote.gid = config.ids.gids.systemd-journal-remote;

    # Allow writing to custom output path
    systemd.services.systemd-journal-remote.serviceConfig.ReadWritePaths =
      [ config.services.journald.remote.output ];

    # Bind socket to Nebula IP only
    systemd.sockets.systemd-journal-remote = {
      after = [ "nebula-online@jakehillion.service" ];
      requires = [ "nebula-online@jakehillion.service" ];
      listenStreams = lib.mkForce [
        ""
        "${config.custom.dns.nebula.ipv4}:19532"
      ];
    };
  };
}
