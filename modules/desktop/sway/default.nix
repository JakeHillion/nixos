{ config, pkgs, lib, ... }:

let
  cfg = config.custom.desktop.sway;
in
{
  options.custom.desktop.sway = {
    enable = lib.mkEnableOption "sway";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/cache/regreet 0755 greeter greeter -"
      "f /var/cache/regreet/cache.toml 0644 greeter greeter -"
    ];
    systemd.services.populate-regreet-cache = {
      description = "Populate /var/cache/regreet/cache.toml to automatically select Sway";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "greeter";
        Group = "greeter";

        ExecStart = "${pkgs.coreutils}/bin/cp ${pkgs.writeText "regreet-cache.toml" ''
          last_user = "jake"

          [user_to_last_sess]
          jake = "Sway"
        ''} /var/cache/regreet/cache.toml";
      };
    };

    programs.regreet = {
      enable = true;

      font = {
        name = "Roboto";
        size = 14;
        package = pkgs.roboto;
      };

      settings = {
        background = {
          path = ./pine-watt-2Hzmz15wGik-unsplash.jpg;
          fit = "Cover";
        };
        GTK = {
          application_prefer_dark_theme = true;
        };
      };
    };

    programs.sway.enable = true;

    home-manager.users."jake" = {
      xdg.configFile."sway/config" = {
        text = with pkgs; let
          config_watcher = pkgs.writeShellScript "sway_config_watcher" ''
            CONFIG_FILE="$HOME/.config/sway/config"

            ${inotify-tools}/bin/inotifywait -m -e close_write "$CONFIG_FILE" | while read -r filename event; do
              ${sway}/bin/swaymsg reload
              ${libnotify}/bin/notify-send "Sway Config Reloaded" "Your Sway configuration has been reloaded."
            done
          '';
        in
        ''
          ### Configure paths filled in by Nix
          set $term "${alacritty}/bin/alacritty"
          set $tmux "${tmux}/bin/tmux"
          set $config_watcher "${config_watcher}"

        '' + builtins.readFile ./config;
      };
    };
  };
}
