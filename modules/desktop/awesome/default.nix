{ config, pkgs, lib, ... }:

{
  services.xserver = {
    enable = true;
    windowManager.awesome.enable = true;
  };

  home-manager.users.jake.xdg.configFile."awesome/rc.lua" =
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

  home-manager.users.jake.programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 8.0;
      };
    };
  };
}
