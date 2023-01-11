{ pkgs, lib, config, ... }:

{
  home-manager.users.root.home.stateVersion = "22.11";
  home-manager.users.jake.home.stateVersion = "22.11";

  imports = [
    ./tmux/default.nix
  ];

  ## Set an empty ZSH config and defer to the global one
  ## This is particularly important for root on tmpfs
  home-manager.users.root.programs.zsh.enable = true;
  home-manager.users.jake.programs.zsh.enable = true;
}
