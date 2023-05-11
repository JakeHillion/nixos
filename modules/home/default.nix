{ pkgs, lib, config, ... }:

{
  imports = [
    ./git.nix
    ./tmux/default.nix
  ];

  config = {
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
  };
}
