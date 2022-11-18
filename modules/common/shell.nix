{ lib, config, ... }:

{
  config.programs.zsh = {
    enable = true;
    histSize = 100000;
    histFile = "$HOME/.zsh_history";

    syntaxHighlighting = {
      enable = true;
    };

    autosuggestions = {
      enable = true;
      highlightStyle = "fg=5";
      strategy = [ "match_prev_cmd" "completion" "history" ];
    };
  };
}

