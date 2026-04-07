{ pkgs, lib, config, ... }:

let
  cfg = config.custom.profiles.devbox;
  user = config.custom.user;
in
{
  options.custom.profiles.devbox = lib.mkEnableOption "devbox profile";

  config = lib.mkIf cfg {
    age.secrets.devbox-cachix-netrc.file = ./devbox-cachix-netrc.age;
    nix.settings.netrc-file = config.age.secrets.devbox-cachix-netrc.path;

    # testquorum private S3 (Cloudflare R2) binary cache.
    # System-level so nix-daemon can authenticate via AWS env vars.
    age.secrets.testquorum-r2-env.rekeyFile = ./testquorum-r2.env.age;

    nix.settings = {
      extra-substituters = [
        "s3://testquorum-nix?endpoint=ba58a56742691d9efc310cca51093d04.r2.cloudflarestorage.com&region=auto&scheme=https"
      ];
      extra-trusted-public-keys = [
        "testquorum-nix-1:bXii6WULJDpQ/VONPLR9Ir+/rA2E67HAQEG1AVjQNnc="
      ];
    };

    systemd.services.nix-daemon = {
      serviceConfig.EnvironmentFile =
        "-${config.age.secrets.testquorum-r2-env.path}";
      after = [ "agenix.service" ];
      wants = [ "agenix.service" ];
    };
    environment.systemPackages = with pkgs; [
      jq # handy and claude always tries to invoke it
    ];

    custom.services.nix-prefetch-repos = {
      enable = true;
      reposPath = "/data/users/${user}/repos";
      user = user;
    };

    custom.impermanence.userExtraDirs.${user} = [
      ".codex"
      ".config/gh"
      ".config/tea"
    ];

    custom.home.claude.enable = true;

    custom.services.protonmail-bridge.enable = true;

    custom.home.nix-trusted-settings = {
      enable = true;
      substituters = [
        "https://exo-internal.cachix.org"
        "https://exo.cachix.org"
        "https://hearthd.cachix.org"
        "https://nixcache.jakehillion.me"
        "https://ogygia.cachix.org"
        "https://sched-ext.cachix.org"
      ];
      trustedPublicKeys = [
        "exo-internal.cachix.org-1:4kcxdKKQspZqUcdXZHOeppVJmVQsaha0U5eHB3Akg5A="
        "exo.cachix.org-1:okq7hl624TBeAR3kV+g39dUFSiaZgLRkLsFBCuJ2NZI="
        "hearthd.cachix.org-1:Lt/GTziCLrilXymMR1tEX1TZkv5ZEqF6JKfyS5aGEqY="
        "nixcache.jakehillion.me-1:HQsjYdrcs3ilS/ngtlbTQXU4Xfsm+va5NN7yoK0wKMg="
        "ogygia.cachix.org-1:xb4bnMPeWgSP81Xs0Vl7ZU4Ez7Ul65qp/EoZ40pDaWo="
        "sched-ext.cachix.org-1:dtoM9QOUUqJs3JkmSgVoKYp9cLY0BrupOqp4DVz35/g="
      ];
    };

    custom.home.opencode.enable = true;

    # Remote builder for aarch64-linux builds
    nix.distributedBuilds = true;
    nix.settings.builders-use-substitutes = true;

    nix.buildMachines = [{
      hostName = "slider.pop.${config.ogygia.domain}";
      system = "aarch64-linux";
      protocol = "ssh-ng";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
      sshUser = "nix-builder";
      sshKey = "${config.custom.impermanence.base}/system/etc/ssh/ssh_host_ed25519_key";
    }];

    home-manager.users.${user} = {
      home = {
        packages = with pkgs; [
          unstable.claude-code
          unstable.codex
          tea
        ];
        shellAliases.aider =
          ''OLLAMA_API_BASE="http://ollama.${config.ogygia.domain}" ${pkgs.aider-chat}/bin/aider --model ollama_chat/qwen2.5-coder:14b'';
      };

      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        pinentry.package = pkgs.pinentry-curses;
      };
    };

    custom.home.neomutt.enable = true;
  };
}
