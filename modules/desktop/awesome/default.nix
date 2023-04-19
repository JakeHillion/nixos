{ config, pkgs, lib, ... }:

let
  cfg = config.custom.desktop.awesome;
in
{
  options.custom.desktop.awesome = {
    enable = lib.mkEnableOption "awesome";
  };

  config = lib.mkIf cfg.enable {
    services.xserver = {
      enable = true;
      windowManager.awesome.enable = true;
    };

    home-manager.users."${config.custom.user}" = {
      xdg.configFile."awesome/rc.lua" =
        let
          awesomeConfig = ''
            -- Configure paths filled in by Nix
            terminal = "${pkgs.alacritty}/bin/alacritty"
            tmux = "${pkgs.tmux}/bin/tmux"
          '' + builtins.readFile ./rc.lua;
        in
        {
          text = awesomeConfig;
          onChange = with pkgs; "echo 'awesome.restart()' | ${awesome}/bin/awesome-client";
        };

      programs.alacritty = {
        enable = true;
        settings = {
          font = {
            size = 8.0;
          };
        };
      };
    };
  };
}
