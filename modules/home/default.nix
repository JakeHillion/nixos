{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home;
  stateVersion = if (builtins.compareVersions config.system.stateVersion "24.05") > 0 then config.system.stateVersion else "22.11";
in
{
  imports = [
    ./git.nix
    ./neovim.nix
    ./neomutt.nix
    ./nix-trusted-settings.nix
    ./tmux/default.nix
  ];

  options.custom.home = {
    defaults = lib.mkEnableOption "home";

    devbox = lib.mkEnableOption "home.devbox";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.defaults {
      home-manager = {
        users.root.home = {
          inherit stateVersion;

          ## Set an empty ZSH config and defer to the global one
          file.".zshrc".text = "";
        };

        users."${config.custom.user}" = {
          home = {
            inherit stateVersion;
          };

          services = {
            ssh-agent.enable = true;
          };

          programs = {
            zoxide = {
              enable = true;
              options = [ "--cmd cd" ];
            };
            zsh.enable = true;

            htop = {
              enable = true;
              settings = {
                show_cpu_frequency = 1;
                show_cpu_temperature = 1;
              };
            };
          };
        };
      };

      # Delegation
      custom.home.git.enable = true;
      custom.home.neovim.enable = true;
      custom.home.tmux.enable = true;
    })

    (lib.mkIf cfg.devbox {
      custom.impermanence = {
        userExtraDirs."${config.custom.user}" = [ ".config/gh" ".config/tea" ];
      };

      # Enable protonmail-bridge service for devboxes
      custom.services.protonmail-bridge.enable = true;

      # Configure nix trusted settings for cachix
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

      home-manager.users."${config.custom.user}" = {
        home = {
          inherit stateVersion;

          packages = with pkgs; [
            unstable.claude-code
            unstable.codex
            tea
          ];
        };

        programs.gpg = {
          enable = true;
        };

        services.gpg-agent = {
          enable = true;
          pinentry.package = pkgs.pinentry-curses;
        };
      };

      # Enable neomutt for devboxes
      custom.home.neomutt.enable = true;
    })
  ];
}
