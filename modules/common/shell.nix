{ lib, config, ... }:

{
  config.programs.zsh = {
    enable = true;
    histSize = 100000;
    syntaxHighlighting = {
      enable = true;
    };
  };
}

