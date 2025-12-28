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

      promptInit = with pkgs; if config.custom.profiles.laptop then ''
        # Battery status in prompt for laptops
        function battery_prompt() {
          local battery_info=$(${pkgs.acpi}/bin/acpi -b 2>/dev/null | head -1)
          if [ -n "$battery_info" ]; then
            local percentage=$(echo "$battery_info" | ${pkgs.gnugrep}/bin/grep -oE '[0-9]+%' | head -1)
            local bat_status=$(echo "$battery_info" | cut -d: -f2 | cut -d, -f1 | tr -d ' ')
            local pct_num=''${percentage%%%}

            if [[ "$bat_status" == "Charging" ]]; then
              echo "⚡$pct_num|"
            elif [ "$pct_num" -lt 20 ]; then
              echo "🪫$pct_num|"
            else
              echo "🔋$pct_num|"
            fi
          fi
        }

        setopt PROMPT_SUBST
        PROMPT='$(battery_prompt)%n@%m:%~/ > '
      '' else ''
        PROMPT='%n@%m:%~/ > '
      '';
    };
  };
}

