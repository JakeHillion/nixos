{ pkgs, lib, config, agenix, ... }:

{
  options.custom.defaults = lib.mkEnableOption "defaults";

  config = lib.mkIf config.custom.defaults {
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
    nixpkgs.config.allowUnfree = true;

    time.timeZone = "Europe/London";
    i18n.defaultLocale = "en_GB.UTF-8";

    users = {
      mutableUsers = false;
      users.${config.custom.user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" ]; # enable sudo
        uid = config.ids.uids.${config.custom.user};
      };
    };

    security.sudo.wheelNeedsPassword = false;

    environment = {
      systemPackages = with pkgs; [
        agenix.packages."${system}".default
        gh
        git
        htop
        nix
        sapling
        vim
      ];
      variables.EDITOR = "vim";
      shellAliases = {
        ls = "ls -p --color=auto";
      };
    };

    networking = rec {
      nameservers = [ "1.1.1.1" "8.8.8.8" ];
      networkmanager.dns = "none";
    };
    networking.firewall.enable = true;

    # Delegation
    custom.ca.consumer.enable = true;
    custom.dns.enable = true;
    custom.home.defaults = true;
    custom.hostinfo.enable = true;
    custom.shell.enable = true;
    custom.ssh.enable = true;
  };
}
