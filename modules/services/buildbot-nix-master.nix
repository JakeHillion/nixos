{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.buildbot-nix-master;
  locations = config.custom.locations.locations.services;

  # Build workers list from locations.nix (string or list of FQDNs)
  workerFqdns =
    let v = locations.buildbot-nix-worker;
    in if builtins.isList v then v else [ v ];

  # Core counts per worker host. Add an entry when a new worker is added.
  workerCores = {
    "boron.cx.${config.ogygia.domain}" = 16;
  };

  workersList = map
    (fqdn: {
      name = lib.head (lib.splitString "." fqdn);
      cores = workerCores.${fqdn} or (throw "buildbot-nix-master: missing cores entry for worker ${fqdn}");
    })
    workerFqdns;

  # Template with placeholder passwords; the real password is spliced in at
  # runtime with jq --arg so arbitrary bytes in the secret are safely escaped.
  workersJsonTemplate = pkgs.writeText "buildbot-workers-template.json"
    (builtins.toJSON (map
      (w: {
        inherit (w) name cores;
        pass = "__WORKER_PASSWORD__";
      })
      workersList));

  workersJsonPath = "/run/buildbot/workers.json";

  generateWorkersJson = pkgs.writeShellScript "generate-buildbot-workers-json" ''
    set -euo pipefail
    pass=$(cat ${lib.escapeShellArg config.age.secrets."buildbot-nix/master-worker-password".path})
    ${pkgs.jq}/bin/jq --arg pass "$pass" 'map(.pass = $pass)' \
      ${workersJsonTemplate} > ${workersJsonPath}
    chown buildbot:buildbot ${workersJsonPath}
    chmod 600 ${workersJsonPath}
  '';
in
{
  options.custom.services.buildbot-nix-master = {
    enable = lib.mkEnableOption "buildbot-nix master (CI coordinator and web UI)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "buildbot.hillion.co.uk";
      description = "Domain name for the buildbot web interface (public)";
    };

    giteaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://gitea.hillion.co.uk";
      description = "URL of the Gitea instance for integration";
    };

    admins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "JakeHillion" ];
      description = "List of admin usernames with full access";
    };

    topic = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "buildbot-nix";
      description = "Gitea repository topic to filter repositories for building";
    };

    oauthId = lib.mkOption {
      type = lib.types.str;
      default = "8b27e890-d276-4c25-9486-f8e97d555da1";
      description = "Gitea OAuth application client ID (from Gitea UI)";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.buildbot = {
      uid = config.ids.uids.buildbot;
      group = "buildbot";
      isSystemUser = true;
    };
    users.groups.buildbot.gid = config.ids.gids.buildbot;

    age.secrets = {
      "buildbot-nix/gitea-oauth-secret" = {
        rekeyFile = ./buildbot-nix/secrets/gitea-oauth-secret.age;
        owner = "buildbot";
        group = "buildbot";
      };
      "buildbot-nix/gitea-webhook-secret" = {
        rekeyFile = ./buildbot-nix/secrets/gitea-webhook-secret.age;
        owner = "buildbot";
        group = "buildbot";
      };
      "buildbot-nix/gitea-token" = {
        rekeyFile = ./buildbot-nix/secrets/gitea-token.age;
        owner = "buildbot";
        group = "buildbot";
      };
      # The master assembles workers.json from the shared worker password.
      "buildbot-nix/master-worker-password" = {
        rekeyFile = ./buildbot-nix/secrets/worker-password.age;
        owner = "buildbot";
        group = "buildbot";
      };
    };

    services.buildbot-nix.master = {
      enable = true;
      domain = cfg.domain;
      workersFile = workersJsonPath;
      admins = cfg.admins;
      authBackend = "gitea";
      # Fronted by Caddy in modules/www/global.nix; emit https:// URLs.
      useHTTPS = true;
      gitea = {
        enable = true;
        instanceUrl = cfg.giteaUrl;
        oauthId = cfg.oauthId;
        oauthSecretFile = config.age.secrets."buildbot-nix/gitea-oauth-secret".path;
        webhookSecretFile = config.age.secrets."buildbot-nix/gitea-webhook-secret".path;
        tokenFile = config.age.secrets."buildbot-nix/gitea-token".path;
        topic = cfg.topic;
      };
    };

    # buildbot-nix unconditionally enables nginx on cfg.domain; we front it
    # with Caddy instead (see modules/www/global.nix), so disable the nginx
    # the upstream module brings in to avoid a :80/:443 bind conflict.
    services.nginx.enable = lib.mkForce false;

    # Listen on both IPv4 and IPv6 for remote worker connections. The outer
    # single quotes make this a Python string literal; backslashes escape the
    # `:` characters in the twisted endpoint descriptor.
    services.buildbot-master.pbPort = ''"tcp:9989:interface=\\:\\:"'';

    systemd.services.buildbot-generate-workers = {
      description = "Generate buildbot workers.json from age secrets";
      wantedBy = [ "buildbot-master.service" ];
      before = [ "buildbot-master.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = generateWorkersJson;
        RemainAfterExit = true;
        RuntimeDirectory = "buildbot";
        RuntimeDirectoryMode = "0750";
        RuntimeDirectoryPreserve = "yes";
      };
    };

    # Ensure /var/lib/buildbot is owned by buildbot; impermanence creates
    # the bind-mount target as root.
    systemd.tmpfiles.rules = [ "d /var/lib/buildbot 0750 buildbot buildbot - -" ];

    # buildbot-master uses /var/lib/buildbot as its home; persist it across
    # impermanence reboots.
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [
      "/var/lib/buildbot"
    ];
  };
}
