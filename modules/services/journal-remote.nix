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
    # Admit journal upload clients on tcp/19532 over Nebula, so ingestion does
    # not depend on the broad legacy-full-access group. Clients carry the
    # journal-client group (see modules/defaults.nix); this is a write-only
    # ingestion endpoint, so the group grants no read access.
    ogygia.nebula.firewall.inbound = [
      { groups = [ "journal-client" ]; port = 19532; proto = "tcp"; }
    ];

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
      after = [ "nebula-online@ogygia.service" ];
      requires = [ "nebula-online@ogygia.service" ];
      listenStreams = lib.mkForce [
        ""
        "${config.custom.dns.nebula.ipv4}:19532"
      ];
    };
  };
}
