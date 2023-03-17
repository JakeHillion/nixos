{ pkgs, config, agenix, ... }:

{
  config.services.nix-daemon.enable = true;

  config.environment.systemPackages = with pkgs; [
    git
    htop
    nix
    vim
  ];
}
