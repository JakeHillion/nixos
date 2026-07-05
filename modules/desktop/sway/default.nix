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

    # indicator-sound-switcher's tray icon (indicator-sound-switcher-symbolic)
    # ships only inside its own package, and only as an SVG. Scope two things
    # to the Sway session (rather than installing anything into a profile) so
    # the tray host (Waybar) can display it:
    #   - expose the package's icons to the icon-theme lookup via XDG_DATA_DIRS
    #   - provide the librsvg gdk-pixbuf loader so the SVG can be rendered
    #     (PNG/JPEG are built into gdk-pixbuf; SVG needs the external loader)
    programs.sway.extraSessionCommands = ''
      export XDG_DATA_DIRS="${pkgs.indicator-sound-switcher}/share:$XDG_DATA_DIRS"
      export GDK_PIXBUF_MODULE_FILE="${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    '';

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

          # Waybar replaces sway's built-in swaybar. Battery is only shown on
          # laptops. Styling is intentionally left to Waybar's built-in default
          # for now; a custom stylesheet can come later.
          waybarConfig = (formats.json { }).generate "waybar-config.json" {
            layer = "top";
            position = "top";

            modules-left = [ "sway/workspaces" "sway/mode" ];
            modules-center = [ "clock" ];
            modules-right = lib.optionals config.custom.profiles.laptop [ "battery" ] ++ [ "tray" ];

            "sway/workspaces".disable-scroll = true;

            clock = {
              interval = 1;
              format = "{:%Y-%m-%d %H:%M:%S}";
            };

            battery = {
              interval = 5;
              states.warning = 20;
              format = "🔋 {capacity}%";
              format-warning = "🪫 {capacity}%";
              format-charging = "⚡ {capacity}%";
            };

            tray = {
              icon-size = 16;
              spacing = 10;
            };
          };
        in
        ''
          ### Configure binary paths from the Nix store
          set $config_watcher "${config_watcher}"
          set $swaylock "${swaylock-effects}/bin/swaylock"
          set $term "${alacritty}/bin/alacritty"
          set $tmux "${tmux}/bin/tmux"
          set $swayosd_client "${swayosd}/bin/swayosd-client"
          set $swayosd_server "${swayosd}/bin/swayosd-server"
          set $indicator_sound_switcher "${indicator-sound-switcher}/bin/indicator-sound-switcher"
          set $waybar "${waybar}/bin/waybar -c ${waybarConfig}"

        '' + builtins.readFile ./config + lib.optionalString (cfg.extraConfig != "") ''

          ### Extra configuration
          ${cfg.extraConfig}
        '';
      };
    };
  };
}
