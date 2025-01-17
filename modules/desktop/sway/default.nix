{ config, pkgs, lib, ... }:

let
  cfg = config.custom.desktop.sway;

  wallpaper = ./Desert_Sands_Louis_Coyle.heic;
in
{
  options.custom.desktop.sway = {
    enable = lib.mkEnableOption "sway";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."sway/timewall" = {
      file = ../../../secrets/sway/timewall/${config.networking.fqdn}.toml.age;
      path = "/home/jake/.config/timewall/config.toml";
      owner = "jake";
      group = "users";
    };
    age.secrets."regreet/timewall" = {
      file = ../../../secrets/sway/timewall/${config.networking.fqdn}.toml.age;
      owner = "greeter";
      group = "greeter";
    };

    systemd.tmpfiles.rules = [
      "d /run/regreet 0755 greeter greeter -"
      "d /var/cache/regreet 0755 greeter greeter -"
      "f /var/cache/regreet/cache.toml 0644 greeter greeter -"

      "d /home/jake/.config 0755 jake users" # so a secret can be placed into it
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
    systemd.services.generate-regreet-wallpaper = {
      description = "Populate /run/regreet/wallpaper with a dynamic symlink";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "greeter";
        Group = "greeter";

        WorkingDirectory = "/run/regreet";
      };

      script = ''
        mkdir -p timewall/cache

        ${pkgs.toml-cli}/bin/toml set ${config.age.secrets."regreet/timewall".path} setter.command '@COMMAND@' >timewall/config.toml
        sed -e "s|\"@COMMAND@\"|['ln', '-fs', '%f', '/run/regreet/wallpaper']|g" -i timewall/config.toml

        TIMEWALL_CONFIG_DIR=timewall TIMEWALL_CACHE_DIR=timewall/cache ${pkgs.unstable.timewall}/bin/timewall set ${wallpaper}
      '';
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
          path = "/run/regreet/wallpaper";
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
            LAST_MOD_TIME=$(stat -c %Y "$CONFIG_FILE")

            echo "Monitoring $CONFIG_FILE for changes..."

            # inotifywait doesn't work on tmpfs used with impermanence. poll instead.
            while true; do
                sleep 5
                CURRENT_MOD_TIME=$(stat -c %Y "$CONFIG_FILE")

                if [ "$CURRENT_MOD_TIME" -ne "$LAST_MOD_TIME" ]; then
                    # File has been modified
                    ${sway}/bin/swaymsg reload
                    LAST_MOD_TIME=$CURRENT_MOD_TIME
                fi
            done
          '';
        in
        ''
          ### Configure binary paths from the Nix store
          set $config_watcher "${config_watcher}"
          set $swaylock "${swaylock-effects}/bin/swaylock"
          set $term "${alacritty}/bin/alacritty"
          set $timewall "${unstable.timewall}/bin/timewall"
          set $tmux "${tmux}/bin/tmux"

          ### Configure extra items from the Nix store
          set $wallpaper ${wallpaper}

        '' + builtins.readFile ./config;
      };
    };
  };
}
