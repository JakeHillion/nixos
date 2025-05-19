{ pkgs, nixpkgs-unstable, lib, config, agenix, ... }:

{
  options.custom.defaults = lib.mkEnableOption "defaults";

  config = lib.mkIf config.custom.defaults {
    hardware.enableAllFirmware = true;
    nix = {
      settings.experimental-features = [ "nix-command" "flakes" ];
      settings = {
        auto-optimise-store = true;
        trusted-users = [ config.custom.user ];
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
        vim

        (writeShellScriptBin "pastry" ''
          ${pkgs.pbcli}/bin/pbcli --host https://privatebin.neb.jakehillion.me "$@" | ${pkgs.gnused}/bin/sed 's/privatebin.neb.jakehillion.me/pastes.hillion.co.uk/g'
        '')
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

    nix.registry.nixpkgs-unstable.to = {
      type = "path";
      path = nixpkgs-unstable;
    };

    services.geoclue2.geoProviderUrl = lib.mkOverride 999 "https://api.beacondb.net/v1/geolocate";

    # Caddy package
    ## TODO: drop to stable once available
    services.caddy.package = pkgs.unstable.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-saKJatiBZ4775IV2C5JLOmZ4BwHKFtRZan94aS5pO90=";
    };

    # Delegation
    custom.ca.consumer.enable = true;
    custom.compressed_ram.enable = true;
    custom.dns.enable = true;
    custom.home.defaults = true;
    custom.hostinfo.enable = true;
    custom.locations.autoServe = true;
    custom.nebula.enable = true;
    custom.prometheus.client.enable = true;
    custom.shell.enable = true;
    custom.ssh.enable = true;
  };
}
