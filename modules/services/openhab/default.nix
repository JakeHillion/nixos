{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.openhab;
  imageName = "openhab/openhab";
  version = config.custom.oci-containers.versions."${imageName}";
in
{
  options.custom.services.openhab = {
    enable = lib.mkEnableOption "openhab";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openhab";
      description = "OpenHAB data directory";
    };
  };

  config = lib.mkIf cfg.enable {
    # Override data directory for impermanence
    custom.services.openhab.dataDir = lib.mkIf config.custom.impermanence.enable
      (lib.mkOverride 999 "${config.custom.impermanence.base}/services/openhab");

    # Create user and group
    users.users.openhab = {
      group = "openhab";
      home = cfg.dataDir;
      createHome = true;
      isSystemUser = true;
      uid = config.ids.uids.openhab;
    };
    users.groups.openhab = {
      gid = config.ids.gids.openhab;
    };

    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 openhab openhab - -"
      "d ${cfg.dataDir}/conf 0755 openhab openhab - -"
      "d ${cfg.dataDir}/userdata 0755 openhab openhab - -"
      "d ${cfg.dataDir}/addons 0755 openhab openhab - -"
    ];

    # OpenHAB systemd service
    systemd.services.openhab = {
      description = "OpenHAB Home Automation";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10";
        User = "openhab";
        Group = "openhab";
        ExecStart = lib.strings.concatStringsSep " " [
          "${pkgs.podman}/bin/podman run"
          "--rm"
          "--name openhab"
          "--publish 28457:8080"
          "--volume ${cfg.dataDir}/conf:/openhab/conf"
          "--volume ${cfg.dataDir}/userdata:/openhab/userdata"
          "--volume ${cfg.dataDir}/addons:/openhab/addons"
          "--volume /etc/localtime:/etc/localtime:ro"
          "--env OPENHAB_HTTP_PORT=8080"
          "--env EXTRA_JAVA_OPTS='-Duser.timezone=Europe/London'"
          "${imageName}:${version}"
        ];
      };
    };

    # Caddy reverse proxy configuration
    services.caddy = {
      enable = true;
      virtualHosts."openhab.${config.ogygia.domain}" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          reverse_proxy http://localhost:28457

          tls {
            ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
          }
        '';
      };
    };

  };
}