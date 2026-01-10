{ lib, config, ... }:

let
  cfg = config.custom.home;
  stateVersion = if (builtins.compareVersions config.system.stateVersion "24.05") > 0 then config.system.stateVersion else "22.11";
in
{
  imports = [
    ./claude
    ./git.nix
    ./neovim.nix
    ./neomutt.nix
    ./nix-trusted-settings.nix
    ./opencode.nix
    ./tmux
  ];

  options.custom.home = {
    defaults = lib.mkEnableOption "home";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.defaults {
      home-manager = {
        users.root = {
          home = {
            inherit stateVersion;

            ## Set an empty ZSH config and defer to the global one
            file.".zshrc".text = "";
          };

          programs.zsh.history.path = lib.mkIf config.custom.impermanence.enable
            (lib.mkOverride 999 "${config.custom.impermanence.base}/users/root/.zsh_history");
        };

        users."${config.custom.user}" = {
          home = {
            inherit stateVersion;
            sessionVariables = lib.attrsets.optionalAttrs config.custom.impermanence.enable {
              _ZO_DATA_DIR = "${config.custom.impermanence.base}/users/${config.custom.user}/.local/share/zoxide";
            };
          };

          services = {
            ssh-agent.enable = true;
          };

          programs = {
            zoxide = {
              enable = true;
              options = [ "--cmd cd" ];
            };
            zsh = {
              enable = true;
              history.path = lib.mkIf config.custom.impermanence.enable
                (lib.mkOverride 999 "${config.custom.impermanence.base}/users/${config.custom.user}/.zsh_history");
            };

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
  ];
}
