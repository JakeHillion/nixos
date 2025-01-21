{ config, pkgs, lib, ... }:

let
  cfg = config.custom.desktop.sway;

  wallpaper = pkgs.fetchurl {
    url = "https://wallpapers.neb.jakehillion.me/JetsonCreative/24_Hour_Cityscapes/24hr-CatalinaAvalonRight.heic";
    sha256 = "08dd78b75e909a9caad5902938da5d7dba46c453d14394b7d203d7a3c0b494b6";
  };

  timewallPr141 = pkgs.unstable.timewall.overrideAttrs (oldAttrs: rec{
    pname = "timewall";
    version = "pr141";

    src = pkgs.fetchFromGitHub {
      owner = "bcyran";
      repo = "timewall";
      rev = "0b1901a19cd2a1d59854be822b79332187e76f0d";
      hash = "sha256-Nc9CRrr4ZTV6VKjftCPElYqWZDR1zrKRwB8JbygBClg=";
    };

    cargoDeps = oldAttrs.cargoDeps.overrideAttrs ({
      name = "${pname}-vendor.tar.gz";
      inherit src;
      outputHash = "sha256-2Jy2S82UalpvsPyfk+KfW1N/VQHs89uix1mWiKB3vHU=";
    });
  });
in
{
  options.custom.desktop.sway = {
    enable = lib.mkEnableOption "sway";
  };

  config = lib.mkIf cfg.enable {
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
    systemd.services.generate-regreet-wallpaper = {
      description = "Populate /var/cache/regreet/wallpaper with a dynamic symlink";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "greeter";
        Group = "greeter";

        WorkingDirectory = "/var/cache/regreet";
      };

      preStart = ''
        mkdir -p timewall/cache

        ln -fs ${pkgs.writeText "timewall-regreet.toml" ''
          [geoclue]
          enable = true
          prefer = true

          [location]
          lat = 51.47789474404557
          lon = -0.0014709754224478695

          [setter]
          command = ['ln', '-fs', '%f', '/var/cache/regreet/wallpaper']
        ''} timewall/config.toml

        TIMEWALL_CONFIG_DIR=timewall TIMEWALL_CACHE_DIR=timewall/cache ${timewallPr141}/bin/timewall set ${wallpaper}
      '';
      script = ''
        TIMEWALL_CONFIG_DIR=timewall TIMEWALL_CACHE_DIR=timewall/cache ${timewallPr141}/bin/timewall set -d
      '';
    };
    services.geoclue2 = {
      enable = true;
      appConfig."timewall" = {
        isAllowed = true;
        isSystem = true;
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
          path = "/var/cache/regreet/wallpaper";
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
      in
      "${pkgs.dbus}/bin/dbus-run-session ${lib.getExe pkgs.cage} ${lib.escapeShellArgs config.programs.regreet.cageArgs} -- ${pkgs.writeShellScript "sleepy_regreet" ''
      ${lib.getExe pkgs.swayidle} -w \
        timeout 300 "${sleep_all_displays}" \
        resume "${wake_all_displays}" &

      ${lib.getExe pkgs.greetd.regreet}
    ''}";

    programs.sway.enable = true;

    home-manager.users."jake" = {
      programs.alacritty = {
        enable = true;
        settings = {
          window = {
            opacity = 0.8;
          };
        };
      };

      xdg.configFile."timewall/config.toml".text = ''
        [geoclue]
        enable = true
        prefer = true

        [location]
        lat = 51.47789474404557
        lon = -0.0014709754224478695

        [setter]
        command = ['${pkgs.sway}/bin/swaymsg', 'output * bg %f fill']
      '';

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
          set $timewall "${timewallPr141}/bin/timewall"
          set $tmux "${tmux}/bin/tmux"

          ### Configure extra items from the Nix store
          set $wallpaper ${wallpaper}

        '' + builtins.readFile ./config;
      };
    };
  };
}
