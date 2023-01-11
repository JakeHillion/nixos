{ pkgs, lib, config, ... }:

{
  config.users.defaultUserShell = pkgs.zsh;

  config.programs.zsh = {
    enable = true;
    histSize = 100000;
    histFile = "$HOME/.zsh_history";

    syntaxHighlighting = {
      enable = true;
    };
  };
}

