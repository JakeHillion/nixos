{ pkgs, lib, config, ... }:

{
  home-manager.users.jake.programs.tmux = {
    enable = true;
    extraConfig = lib.readFile ./.tmux.conf;
  };
}
