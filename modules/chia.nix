{ config, pkgs, lib, ... }:

let
  cfg = config.custom.chia;

  ctl = pkgs.writeScriptBin "chiactl" ''
    #! ${pkgs.runtimeShell}
    set -e
    sudo ${pkgs.podman}/bin/podman exec chia chia "$@"
  '';
in
{
  options.custom.chia = {
    enable = lib.mkEnableOption "chia";

    path = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/chia";
    };
    keyFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    plotDirectories = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ ctl ];

    users.groups.chia.gid = config.ids.gids.chia;
    users.users.chia = {
      home = cfg.path;
      createHome = true;
      isSystemUser = true;
      group = "chia";
      uid = config.ids.uids.chia;
    };

    virtualisation.oci-containers.containers.chia =
      let
        imageName = "ghcr.io/chia-network/chia";
        ver = config.custom.oci-containers.versions."${imageName}";
      in
      {
        image = "${imageName}:${ver}";
        ports = [ "8444" ];
        extraOptions = [
          "--uidmap=0:${toString config.users.users.chia.uid}:1"
          "--gidmap=0:${toString config.users.groups.chia.gid}:1"
        ];
        volumes = [
          "${cfg.keyFile}:/run/keyfile"
          "${cfg.path}/.chia:/root/.chia"
        ] ++ lib.lists.imap0 (i: v: "${v}:/plots${toString i}") cfg.plotDirectories;
        environment = {
          keys = "/run/keyfile";
          plots_dir = lib.strings.concatImapStringsSep ":" (i: v: "/plots${toString i}") cfg.plotDirectories;
        };
      };

    systemd.tmpfiles.rules = [
      "d ${cfg.path} 0700 chia chia - -"
      "d ${cfg.path}/.chia 0700 chia chia - -"
    ];

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 8444 ];
    };
  };
}


