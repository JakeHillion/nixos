{ config, pkgs, nixpkgs, nixpkgs-unstable, ... }:

{
  config = {
    system.stateVersion = 4;

    networking.hostName = "jakehillion-mba-m2-15";

    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
      };

      registry = {
        nixpkgs.flake = nixpkgs;
        nixpkgs-unstable.flake = nixpkgs-unstable;
      };
    };

    nixpkgs.config.allowUnfree = true;

    programs.zsh.enable = true;

    security.pam.services.sudo_local.touchIdAuth = true;

    environment.systemPackages = with pkgs; [
      fd
      htop
      jujutsu
      mosh
      neovim
      nix
      ripgrep
    ];
  };
}
