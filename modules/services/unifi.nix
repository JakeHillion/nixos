{ config, pkgs, lib, ... }:
let
  cfg = config.custom.services.unifi;

  image = pkgs.unifi-os-server-image;

  stateDir =
    if config.custom.impermanence.enable
    then "${config.custom.impermanence.base}/services/unifi"
    else "/var/lib/unifi-os-server";

  # Container paths that hold persistent state. The installer bind-mounts the
  # /var/lib entries (see mounts.json in the installer); /data holds the
  # instance UUID written by the image entrypoint.
  persist = {
    data = "/data";
    unifi = "/var/lib/unifi";
    mongodb = "/var/lib/mongodb";
    rabbitmq-ssl = "/etc/rabbitmq/ssl";
  };

  # UOS_UUID identifies the instance and must stay constant across restarts.
  # Generated once and kept in the state directory.
  uuidEnvFile = "${stateDir}/uos.env";
  ensureUuid = pkgs.writeShellScript "unifi-os-server-uuid" ''
    set -eu
    if [ ! -s "${uuidEnvFile}" ]; then
      echo "UOS_UUID=$(${pkgs.util-linux}/bin/uuidgen)" > "${uuidEnvFile}"
      chmod 600 "${uuidEnvFile}"
    fi
  '';
in
{
  options.custom.services.unifi = {
    enable = lib.mkEnableOption "unifi";
  };

  config = lib.mkIf cfg.enable {
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ stateDir ];

    systemd.tmpfiles.rules =
      [ "d ${stateDir} 0700 root root - -" ]
      ++ lib.mapAttrsToList (name: _: "d ${stateDir}/${name} 0700 root root - -") persist;

    virtualisation.oci-containers.containers.unifi = {
      imageFile = image;
      image = image.imageTag;

      # Device-facing ports are published on all interfaces; the GUI (443 in
      # the container) is bound to localhost and fronted by Caddy below.
      ports = [
        "8080:8080" # device inform
        "3478:3478/udp" # STUN
        "10003:10003/udp" # device discovery
        "127.0.0.1:11443:443" # GUI/API (reverse-proxied)
      ];

      environment = {
        PRODUCT_NAME = "uosserver";
        FIRMWARE_PLATFORM = "linux-x64";
        APP_VERSION = image.version;
      };

      volumes =
        [ "/sys/fs/cgroup:/sys/fs/cgroup:rw" ]
        ++ lib.mapAttrsToList (name: ctr: "${stateDir}/${name}:${ctr}") persist;

      # UniFi OS runs a full systemd inside the container (exec /sbin/init),
      # orchestrating MongoDB, RabbitMQ, nginx and friends as separate users.
      extraOptions = [
        "--env-file=${uuidEnvFile}"
        "--cgroupns=host"
        "--tmpfs=/run:exec"
        "--tmpfs=/run/lock"
        "--tmpfs=/tmp:exec"
        "--tmpfs=/var/lib/journal"
        "--cap-drop=all"
        "--cap-add=SYS_ADMIN"
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
        "--cap-add=NET_BIND_SERVICE"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=DAC_READ_SEARCH"
        "--cap-add=FOWNER"
        "--cap-add=CHOWN"
        "--cap-add=SETUID"
        "--cap-add=SETGID"
        "--cap-add=KILL"
        "--cap-add=SYS_CHROOT"
        "--cap-add=SYS_PTRACE"
        "--cap-add=SYS_RESOURCE"
        "--cap-add=AUDIT_WRITE"
        "--cap-add=MKNOD"
      ];
    };

    systemd.services.podman-unifi.serviceConfig.ExecStartPre = lib.mkBefore [
      "${ensureUuid}"
    ];

    services.caddy = {
      enable = true;
      virtualHosts."unifi.hillion.co.uk".extraConfig = ''
        reverse_proxy https://localhost:11443 {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    };

    networking.firewall = {
      allowedTCPPorts = [ 80 443 8080 ];
      allowedUDPPorts = [ 3478 10003 ];
    };
  };
}
