{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.isponsorblocktv;

  imageName = "ghcr.io/dmunozv04/isponsorblocktv";
  ver = config.custom.oci-containers.versions."${imageName}";

  ctl = pkgs.writeScriptBin "isponsorblocktv-config" ''
    #! ${pkgs.runtimeShell}
    set -e

    sudo systemctl stop podman-isponsorblocktv

    sudo ${pkgs.podman}/bin/podman run           \
        --rm -it                                 \
        --uidmap=0:${toString config.users.users.isponsorblocktv.uid}:1 \
        --gidmap=0:${toString config.users.groups.isponsorblocktv.gid}:1 \
        -v ${cfg.dataDir}:/app/data              \
        ${imageName}:${ver} \
        --setup-cli

    sudo systemctl start podman-isponsorblocktv
  '';
in
{
  options.custom.services.isponsorblocktv = {
    enable = lib.mkEnableOption "isponsorblocktv";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/isponsorblocktv";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ ctl ];

    users.groups.isponsorblocktv = {
      gid = config.ids.gids.isponsorblocktv;
    };
    users.users.isponsorblocktv = {
      home = cfg.dataDir;
      createHome = true;
      isSystemUser = true;
      group = "isponsorblocktv";
      uid = config.ids.uids.isponsorblocktv;
    };

    virtualisation.oci-containers.containers.isponsorblocktv = {
      image = "${imageName}:${ver}";
      extraOptions = [
        "--uidmap=0:${toString config.users.users.isponsorblocktv.uid}:1"
        "--gidmap=0:${toString config.users.groups.isponsorblocktv.gid}:1"
      ];
      volumes = [ "${cfg.dataDir}:/app/data" ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 isponsorblocktv isponsorblocktv - -"
    ];
  };
}

