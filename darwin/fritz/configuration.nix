{ nixpkgs, nixpkgs-unstable, pkgs, ... }:

{
  config = {
    system.stateVersion = 7;
    system.primaryUser = "jake";

    networking.hostName = "fritz";

    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "root" "jake" ];
      };

      registry = {
        nixpkgs.flake = nixpkgs;
        nixpkgs-unstable.flake = nixpkgs-unstable;
      };
    };

    nixpkgs.config.allowUnfree = true;

    programs.zsh.enable = true;

    # macOS 27 denies writes to /etc/pam.d even as root, so nix-darwin can't
    # link sudo_local. It manages the file by default, so disable it entirely.
    security.pam.services.sudo_local.enable = false;

    environment.systemPackages = with pkgs; [
      fd
      git
      htop
      jujutsu
      mosh
      neovim
      ripgrep
    ];
  };
}
