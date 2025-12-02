{ config, pkgs, lib, ... }:

let
  cfg = config.custom.desktop.sway;
in
{
  options.custom.desktop.sway = {
    enable = lib.mkEnableOption "sway";
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra configuration to append to the Sway config file";
    };
    greeterRotation = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "90" "180" "270" "normal" "flipped" "flipped-90" "flipped-180" "flipped-270" ]);
      default = null;
      description = "Rotation transformation for the greeter display (uses wlr-randr transform values)";
    };
  };

  config = lib.mkIf cfg.enable {
    custom.desktop.timewall = {
      enable = true;
      wallpaper = pkgs.fetchurl {
        url = "https://wallpapers.${config.ogygia.domain}/JetsonCreative/24_Hour_Cityscapes/24hr-CatalinaAvalonRight.heic";
        sha256 = "08dd78b75e909a9caad5902938da5d7dba46c453d14394b7d203d7a3c0b494b6";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/cache/regreet 0755 greeter greeter -"
      "f /var/cache/regreet/cache.toml 0644 greeter greeter -"
      "Z /var/cache/regreet - greeter greeter -"

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

    programs.regreet = {
      enable = true;

      font = {
        name = "Roboto";
        size = 14;
        package = pkgs.roboto;
      };

      settings = {
        background = {
          path = "/var/cache/timewall/current_wall";
          fit = "Cover";
        };
        GTK = {
          application_prefer_dark_theme = true;
        };
      };
    };
    services.greetd.settings.default_session.command =
      let
        cmd_all_displays = cmd: pkgs.writeShellScript "sleep_all_displays" ''
          ${lib.getExe pkgs.wlr-randr} --json \
            | ${lib.getExe pkgs.jq} -r '.[].name' \
            | xargs -I{} ${lib.getExe pkgs.wlr-randr} --output {} --${cmd}
        '';

        sleep_all_displays = cmd_all_displays "off";
        wake_all_displays = cmd_all_displays "on";

        rotate_displays = lib.optionalString (cfg.greeterRotation != null) ''
          # Apply rotation to all displays
          ${lib.getExe pkgs.wlr-randr} --json \
            | ${lib.getExe pkgs.jq} -r '.[].name' \
            | xargs -I{} ${lib.getExe pkgs.wlr-randr} --output {} --transform ${cfg.greeterRotation}
        '';
      in
      "${pkgs.dbus}/bin/dbus-run-session ${lib.getExe pkgs.cage} ${lib.escapeShellArgs config.programs.regreet.cageArgs} -- ${pkgs.writeShellScript "sleepy_regreet" ''
      ${rotate_displays}

      ${lib.getExe pkgs.swayidle} -w \
        timeout 300 "${sleep_all_displays}" \
        resume "${wake_all_displays}" &

      ${lib.getExe pkgs.regreet}
    ''}";

    programs.sway.enable = true;

    # Enable Firefox for desktop environment
    custom.desktop.firefox.enable = true;

    home-manager.users."jake" = {
      programs.alacritty = {
        enable = true;
        settings = {
          window = {
            opacity = 0.8;
          };
        };
      };


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

          status_command = pkgs.writeShellScript "sway_status" (
            if config.custom.laptop then ''
              # Get battery information using acpi
              BATTERY_INFO=$(${pkgs.acpi}/bin/acpi -b 2>/dev/null | head -1)
              if [ -n "$BATTERY_INFO" ]; then
                BATTERY_CAPACITY=$(echo "$BATTERY_INFO" | ${pkgs.gnugrep}/bin/grep -oE '[0-9]+%' | head -1 | tr -d '%')
                BATTERY_STATUS=$(echo "$BATTERY_INFO" | cut -d: -f2 | cut -d, -f1 | tr -d ' ')

                # Set battery icon based on status and level
                if [ "$BATTERY_STATUS" = "Charging" ]; then
                  BATTERY_ICON="⚡"
                elif [ "$BATTERY_CAPACITY" -lt 20 ]; then
                  BATTERY_ICON="🪫"
                else
                  BATTERY_ICON="🔋"
                fi

                echo "$BATTERY_ICON$BATTERY_CAPACITY | $(date +'%Y-%m-%d %X')"
              else
                date +'%Y-%m-%d %X'
              fi
            '' else ''
              date +'%Y-%m-%d %X'
            ''
          );
        in
        ''
          ### Configure binary paths from the Nix store
          set $config_watcher "${config_watcher}"
          set $status_command "${status_command}"
          set $swaylock "${swaylock-effects}/bin/swaylock"
          set $term "${alacritty}/bin/alacritty"
          set $tmux "${tmux}/bin/tmux"

        '' + builtins.readFile ./config + lib.optionalString (cfg.extraConfig != "") ''

          ### Extra configuration
          ${cfg.extraConfig}
        '';
      };
    };
  };
}
