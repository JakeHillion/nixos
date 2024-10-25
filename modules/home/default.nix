{ pkgs, lib, config, ... }:

{
  imports = [
    ./git.nix
    ./neovim.nix
    ./tmux/default.nix
  ];

  options.custom.home.defaults = lib.mkEnableOption "home";

  config = lib.mkIf config.custom.home.defaults {
    home-manager = {
      users.root.home = {
        stateVersion = "22.11";

        ## Set an empty ZSH config and defer to the global one
        file.".zshrc".text = "";
      };

      users."${config.custom.user}".home = {
        stateVersion = "22.11";

        ## Set an empty ZSH config and defer to the global one
        file.".zshrc".text = "";
      };
    };

    # Delegation
    custom.home.git.enable = true;
    custom.home.neovim.enable = true;
    custom.home.tmux.enable = true;
  };
}
