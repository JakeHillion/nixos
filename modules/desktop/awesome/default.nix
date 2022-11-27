{ config, pkgs, lib, ... }:

{
  services.xserver = {
    enable = true;
    windowManager.awesome.enable = true;
  };
}
