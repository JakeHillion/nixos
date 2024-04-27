{ pkgs, lib, config, ... }:

let
  cfg = config.custom.shell;
in
{
  imports = [
    ./update_scripts.nix
  ];

  options.custom.shell = {
    enable = lib.mkEnableOption "shell";
  };

  config = lib.mkIf cfg.enable {
    custom.shell.update_scripts.enable = true;

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

