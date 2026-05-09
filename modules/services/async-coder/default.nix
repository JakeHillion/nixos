{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.async_coder;
  fqdnParts = lib.splitString "." config.networking.fqdn;
  shortHost = "${builtins.elemAt fqdnParts 0}.${builtins.elemAt fqdnParts 1}";
in
{
  options.custom.services.async_coder = {
    enable = lib.mkEnableOption "async-coder";
  };

  config = lib.mkIf cfg.enable {
    age.secrets = lib.genAttrs
      (map (s: "async-coder/${s}") [
        "${shortHost}.password"
        "gitea-token"
      ])
      (name: {
        file = ./. + "/${lib.removePrefix "async-coder/" name}.age";
        owner = "async-coder";
        group = "async-coder";
      });

    custom.services.llm_proxy.enable = true;

    users.users.async-coder.uid = config.ids.uids.async-coder;
    users.groups.async-coder.gid = config.ids.gids.async-coder;

    users.users.async-coder.subUidRanges = lib.mkIf config.virtualisation.podman.enable
      [{ startUid = 100000; count = 65536; }];
    users.users.async-coder.subGidRanges = lib.mkIf config.virtualisation.podman.enable
      [{ startGid = 100000; count = 65536; }];

    systemd.services.async-coder = lib.mkIf config.virtualisation.podman.enable {
      path = [
        config.virtualisation.podman.package
        (pkgs.runCommand "docker-podman-shim" { } ''
          mkdir -p $out/bin
          ln -s ${config.virtualisation.podman.package}/bin/podman $out/bin/docker
        '')
      ];
      serviceConfig = {
        NoNewPrivileges = lib.mkForce false;
        RuntimeDirectory = "async-coder";
        RuntimeDirectoryMode = "0700";
        Environment = [
          "XDG_RUNTIME_DIR=/run/async-coder"
          "DOCKER_HOST=unix:///run/async-coder/podman/podman.sock"
        ];
      };
    };

    systemd.services.async-coder-podman-socket = lib.mkIf config.virtualisation.podman.enable {
      description = "Rootless podman API socket for async-coder";
      wantedBy = [ "async-coder.service" ];
      before = [ "async-coder.service" ];
      serviceConfig = {
        Type = "simple";
        User = "async-coder";
        Group = "async-coder";
        RuntimeDirectory = "async-coder/podman";
        RuntimeDirectoryMode = "0700";
        Environment = [ "XDG_RUNTIME_DIR=/run/async-coder" ];
        ExecStart = "${config.virtualisation.podman.package}/bin/podman system service --time=0 unix:///run/async-coder/podman/podman.sock";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    services.async-coder = {
      enable = true;
      opencode-package = pkgs.unstable.opencode;
      settings = {
        homeserver_url = "https://matrix.hillion.co.uk";
        username = shortHost;
        password_file = config.age.secrets."async-coder/${shortHost}.password".path;

        avatar = ./${shortHost}.png;
        store_path = "/var/lib/async-coder/store";
        device_display_name = "async-coder";
        trusted_users = [ "@jake:hillion.co.uk" ];
        root_space = "!WhggIMMfLMutJEDsdv:hillion.co.uk";

        git_author_name = "Jake Hillion";
        git_author_email = "jake@hillion.co.uk";

        forges = {
          gitea = {
            type = "gitea";
            url = "https://gitea.hillion.co.uk";
            ssh_url = "git@ssh.gitea.hillion.co.uk";
            token_file = config.age.secrets."async-coder/gitea-token".path;

            repositories = [
              { owner = "JakeHillion"; name = "async-coder"; envrc = true; }
              { owner = "JakeHillion"; name = "nixos"; jujutsu_mode = true; }
              { owner = "JakeHillion"; name = "personal-agent"; envrc = true; }
              { owner = "JakeHillion"; name = "testquorum"; envrc = true; }
            ];
          };

          github = {
            type = "github";

            repositories = [
              { owner = "JakeHillion"; name = "hearthd"; envrc = true; }
              { owner = "JakeHillion"; name = "ogygia-nix"; envrc = true; }
              { owner = "testquorum"; name = "testquorum-rs"; envrc = true; }
            ];
          };
        };

        opencode = {
          api_key_file = pkgs.writeText "async-coder-dummy-key" "unused";
          api_url = "http://127.0.0.1:9100/v1/batch/10000";
          model = "moonshotai/kimi-k2.6";
          cheap_fast_model = "minimax/minimax-m2.5";
          provider = "llm-proxy";
          base_port = 18900;
        };
      };
    };
  };
}
