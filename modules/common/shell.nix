{ pkgs, lib, config, ... }:

{
  config = {
    users.defaultUserShell = pkgs.zsh;

    environment.systemPackages = with pkgs; [ direnv ];
    nix.settings = {
      keep-outputs = true;
      keep-derivations = true;
    };
    custom.impermanence.userExtraDirs.jake = [
      ".local/share/direnv"
    ];

    programs.thefuck.enable = true;

    programs.zsh = {
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
        "nixos-rebuild" = "nixos-rebuild --flake \"/etc/nixos#${config.networking.fqdn}\"";
      };

      interactiveShellInit = with pkgs; ''
        eval "$(${direnv}/bin/direnv hook zsh)"
        source ${nix-direnv}/share/nix-direnv/direnvrc
      '';
    };
  };
}

