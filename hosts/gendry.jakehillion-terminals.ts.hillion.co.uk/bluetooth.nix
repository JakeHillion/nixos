{ config, pkgs, lib, ... }:

{
  config.hardware.bluetooth.enable = true;
  config.environment.systemPackages = with pkgs; [ bluez-tools ];
}
