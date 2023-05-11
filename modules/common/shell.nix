{ pkgs, lib, config, ... }:

{
  config.users.defaultUserShell = pkgs.zsh;

  config.programs.thefuck.enable = true;
  config.programs.zsh = {
    enable = true;
    histSize = 1000000;
    histFile = "$HOME/.zsh_history";

    setOptions = [
      "INC_APPEND_HISTORY"
      "SHARE_HISTORY"
    ];

    syntaxHighlighting = {
      enable = true;
    };

    shellAliases = {
      "nixos-rebuild" = "nixos-rebuild --flake \"/etc/nixos#$(hostname -f)\"";
    };
  };
}

