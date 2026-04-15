{ config, lib, ... }:

let
  cfg = config.custom.services.buildbot-nix-worker;
  locations = config.custom.locations.locations.services;

  # Get the master host from locations
  masterHost = locations.buildbot-nix-master;
in
{
  options.custom.services.buildbot-nix-worker = {
    enable = lib.mkEnableOption "buildbot-nix worker (build runner)";

    masterUrl = lib.mkOption {
      type = lib.types.str;
      default = "tcp:host=${masterHost}:port=9989";
      description = "URL of the buildbot master to connect to";
    };
  };

  config = lib.mkIf cfg.enable {
    # User and group definitions
    users.users.buildbot-worker = {
      uid = config.ids.uids.buildbot-worker;
      group = "buildbot-worker";
      isSystemUser = true;
    };
    users.groups.buildbot-worker.gid = config.ids.gids.buildbot-worker;

    # Worker needs the password secret
    age.secrets."buildbot-nix/worker-password" = {
      rekeyFile = ./buildbot-nix/secrets/worker-password.age;
      owner = "buildbot-worker";
      group = "buildbot-worker";
    };

    services.buildbot-nix.worker = {
      enable = true;
      workerPasswordFile = config.age.secrets."buildbot-nix/worker-password".path;
      masterUrl = cfg.masterUrl;
    };

    # Impermanence support for worker
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [
      "/var/lib/buildbot-worker"
    ];
  };
}
