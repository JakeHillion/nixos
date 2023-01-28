{ config, pkgs, lib, ... }:

{
  services.xserver = {
    enable = true;
    windowManager.awesome.enable = true;
  };

  home-manager.users.jake.xdg.configFile."awesome/rc.lua" = {
    source = ./rc.lua;
    onChange = with pkgs; "echo 'awesome.restart()' | ${awesome}/bin/awesome-client";
  };
}
