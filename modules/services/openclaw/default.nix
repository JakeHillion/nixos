{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.openclaw;
  settingsFormat = pkgs.formats.json { };

  openclaw-skills-src = pkgs.fetchFromGitHub {
    owner = "openclaw";
    repo = "skills";
    rev = "debdfe5ace835cae781e0f7bd9c94288d6e9ec07";
    hash = "sha256-ThdIaoSrHfQF4XZIJ3UHHoupXYLHYUMy6bI7XrVxfOY=";
  };

  skillsDir = pkgs.runCommand "openclaw-skills" { } ''
    mkdir -p $out/track17
    cp -r ${openclaw-skills-src}/skills/tristanmanchester/track17/* $out/track17/

    # Patch SKILL.md to use the wrapper binary instead of python3 {baseDir}/...
    substituteInPlace $out/track17/SKILL.md \
      --replace-quiet 'python3 {baseDir}/scripts/track17.py' 'track17'

    # Remove anyBins requirement — the Nix wrapper bundles python3 directly
    substituteInPlace $out/track17/SKILL.md \
      --replace-quiet '"anyBins":["python3","python"],' ""
  '';

  track17-wrapper = pkgs.writeShellScriptBin "track17" ''
    exec ${pkgs.python3}/bin/python3 ${skillsDir}/track17/scripts/track17.py "$@"
  '';

  openclawConfig = {
    gateway.mode = "local";
    gateway.trustedProxies = [ "127.0.0.1" "::1" ];

    channels.matrix = {
      enabled = true;
      homeserver = "https://matrix.hillion.co.uk";
      userId = "@openclaw:hillion.co.uk";
      password = "\${MATRIX_PASSWORD}";
      encryption = true;
      deviceName = "OpenClaw";
      dm = {
        policy = "allowlist";
        allowFrom = [ "@jake:hillion.co.uk" ];
      };
      groupPolicy = "disabled";
    };

    models.providers.together = {
      baseUrl = "https://api.together.ai/v1";
      apiKey = "\${TOGETHER_API_KEY}";
      api = "openai-completions";
      models = [{ id = "moonshotai/Kimi-K2.5"; name = "Kimi K2.5"; }];
    };
    agents.defaults.model.primary = "together/moonshotai/Kimi-K2.5";

    tools = {
      profile = "minimal";
      alsoAllow = [
        "cron"
        "exec"
        "group:fs"
      ];
      exec = {
        host = "gateway";
        security = "allowlist";
        ask = "on-miss";
      };
      fs.workspaceOnly = true;
      web.fetch.enabled = false;
      web.search.enabled = false;
    };

    skills.entries.track17.enabled = true;

    approvals.exec = {
      enabled = true;
      mode = "session";
    };

    plugins.entries.matrix.enabled = true;
  };
  configFile = settingsFormat.generate "openclaw.json" openclawConfig;
  dataDir = "/var/lib/openclaw";
in
{
  options.custom.services.openclaw.enable = lib.mkEnableOption "openclaw";

  config = lib.mkIf cfg.enable {
    custom.impermanence.extraDirs =
      lib.mkIf config.custom.impermanence.enable [ dataDir ];

    age.secrets."openclaw/environment" = {
      file = ./environment.age;
      owner = "openclaw";
      group = "openclaw";
    };

    users.users.openclaw = {
      uid = config.ids.uids.openclaw;
      isSystemUser = true;
      group = "openclaw";
      home = dataDir;
      shell = pkgs.bash;
      packages = [ track17-wrapper ];
    };
    users.groups.openclaw.gid = config.ids.gids.openclaw;

    custom.www.nebula = {
      enable = true;
      virtualHosts."openclaw.${config.ogygia.domain}" = {
        extraConfig = ''
          reverse_proxy http://localhost:3000
        '';
      };
    };

    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        OPENCLAW_CONFIG_PATH = toString configFile;
        OPENCLAW_STATE_DIR = dataDir;
        OPENCLAW_NIX_MODE = "1";
        NODE_PATH = "${pkgs.openclaw-matrix-plugin}/node_modules";
        NODE_ENV = "production";
        TRACK17_DATA_DIR = "${dataDir}/track17";
        SHELL = "${pkgs.bash}/bin/bash";
      };

      serviceConfig = {
        Type = "simple";
        ExecStartPre = pkgs.writeShellScript "openclaw-setup-skills" ''
          rm -rf ${dataDir}/.openclaw/workspace/skills
          mkdir -p ${dataDir}/.openclaw/workspace/skills
          cp -rL ${skillsDir}/* ${dataDir}/.openclaw/workspace/skills/
        '';
        ExecStart = "${pkgs.openclaw-gateway}/bin/openclaw gateway --port 3000";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = dataDir;
        User = "openclaw";
        Group = "openclaw";
        StateDirectory = "openclaw";
        EnvironmentFile = [ config.age.secrets."openclaw/environment".path ];

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Node.js JIT
        ReadWritePaths = [ dataDir ];
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        UMask = "0077";
      };

      path = [ pkgs.bash ];
    };
  };
}
