{ pkgs, lib, config, ... }:

let
  cfg = config.custom.profiles.devbox;
  user = config.custom.user;
in
{
  options.custom.profiles.devbox.enable = lib.mkEnableOption "Devbox profile";

  config = lib.mkIf cfg.enable {
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
        "https://hearthd.cachix.org"
        "https://ogygia.cachix.org"
        "https://sched-ext.cachix.org"
      ];
      trustedPublicKeys = [
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
