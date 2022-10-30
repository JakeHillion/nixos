{ pkgs, lib, config, ... }:

{
  imports = [
    ./shell.nix
    ./ssh.nix
    ./tailscale.nix
  ];
  
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
    settings = {
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 90d";
    };
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  users = {
    mutableUsers = false;
    users."jake" = {
      isNormalUser = true;
      extraGroups = [ "wheel" ]; # enable sudo
      shell = pkgs.zsh;
    };
  };

  security.sudo.wheelNeedsPassword = false;

  environment = {
    systemPackages = with pkgs; [
      git
      htop
      nix
      vim
    ];
    variables.EDITOR = "vim";
    shellAliases = {
      ls = "ls -p --color=auto";
    };
  };

  networking = rec {
    nameservers = [ "1.1.1.1" "8.8.8.8" "100.100.100.100" ];
    networkmanager.dns = "none";
  };
  networking.firewall.enable = true;
}