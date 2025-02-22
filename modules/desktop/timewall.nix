{ pkgs, config, lib, ... }:

let
  cfg = config.custom.desktop.timewall;

  baseConfig = {
    geoclue = {
      enable = true;
      prefer = true;
    };
    location = {
      lat = 51.47789474404557;
      lon = -0.0014709754224478695;
    };
  };

  mkConfigDir = config:
    let configFormat = pkgs.formats.toml { }; in pkgs.runCommand "timewall-config" { } ''
      mkdir -p $out
      ln -fs ${configFormat.generate "timewall-config.toml" (baseConfig // config)} $out/config.toml
    '';

  cache = pkgs.runCommand "timewall-cache" { } ''
    mkdir $out

    export TIMEWALL_CONFIG_DIR=${mkConfigDir { setter.command = ["${pkgs.coreutils}/bin/true"]; }}
    export TIMEWALL_CACHE_DIR=$out

    ${pkgs.unstable.timewall}/bin/timewall set -v ${cfg.wallpaper}
  '';
in
{
  options.custom.desktop.timewall = {
    enable = lib.mkEnableOption "timewall";

    wallpaper = lib.mkOption {
      type = lib.types.path;
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.timewall = { };
    users.users.timewall = {
      group = "timewall";
      isSystemUser = true;
      createHome = false;
    };

    services.geoclue2 = {
      enable = true;
      appConfig."timewall" = {
        isAllowed = true;
        isSystem = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/cache/timewall 0755 timewall timewall -"
    ];
    systemd.services.create-timewall-symlink = {
      description = "Dynamically update /var/cache/timewall/current_wall with a timewall wallpaper.";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "timewall";
        Group = "timewall";

        WorkingDirectory = "/var/cache/timewall";
      };

      environment = {
        TIMEWALL_CACHE_DIR = "${cache}";
        TIMEWALL_CONFIG_DIR = "${mkConfigDir { setter.command = [ "ln" "-fs" "%f" "current_wall" ]; }}";
      };
      script = ''
        ${pkgs.unstable.timewall}/bin/timewall set -v -d
      '';
    };

    home-manager.users."jake" = {
      systemd.user.services."timewall-sway" = {
        Unit.Description = "Dynamically update Sway wallpaper with timewall.";

        Service = {
          Environment = [
            "TIMEWALL_CACHE_DIR=${cache}"
            "TIMEWALL_CONFIG_DIR=${mkConfigDir { setter.command = [ "${pkgs.sway}/bin/swaymsg" "output * bg %f fill" ]; }}"
          ];
          ExecStart = "${pkgs.unstable.timewall}/bin/timewall set -v -d";
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
