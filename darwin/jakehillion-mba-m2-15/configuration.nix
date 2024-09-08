{ config, pkgs, ... }:

{
  config = {
    system.stateVersion = 4;

    networking.hostName = "jakehillion-mba-m2-15";

    nix = {
      useDaemon = true;
    };

    programs.zsh.enable = true;

    security.pam.enableSudoTouchIdAuth = true;

    environment.systemPackages = with pkgs; [
      fd
      htop
      mosh
      neovim
      nix
      ripgrep
      sapling
    ];
  };
}
