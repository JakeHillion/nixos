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
        "https://exo.cachix.org"
        "https://exo-internal.cachix.org"
        "https://hearthd.cachix.org"
        "https://ogygia.cachix.org"
        "https://sched-ext.cachix.org"
      ];
      trustedPublicKeys = [
        "exo.cachix.org-1:okq7hl624TBeAR3kV+g39dUFSiaZgLRkLsFBCuJ2NZI="
        "exo-internal.cachix.org-1:4kcxdKKQspZqUcdXZHOeppVJmVQsaha0U5eHB3Akg5A="
        "hearthd.cachix.org-1:Lt/GTziCLrilXymMR1tEX1TZkv5ZEqF6JKfyS5aGEqY="
        "ogygia.cachix.org-1:xb4bnMPeWgSP81Xs0Vl7ZU4Ez7Ul65qp/EoZ40pDaWo="
        "sched-ext.cachix.org-1:dtoM9QOUUqJs3JkmSgVoKYp9cLY0BrupOqp4DVz35/g="
      ];
    };

    custom.home.opencode.enable = true;

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
