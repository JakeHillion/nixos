{ pkgs, nixpkgs-unstable, lib, config, agenix, ... }:

{
  options.custom.defaults = lib.mkEnableOption "defaults";

  config = lib.mkIf config.custom.defaults {
    ogygia = {
      enable = true;
      domain = "neb.jakehillion.me";

      zookeeper = {
        enable = true;
        endpoints = config.custom.services.zookeeper.clientHosts;
      };
    };

    hardware.enableAllFirmware = true;
    nix = {
      settings = lib.mkMerge [
        {
          auto-optimise-store = true;
          experimental-features = [ "nix-command" "flakes" ];
          trusted-users = [ config.custom.user ];
        }

        (lib.mkIf config.custom.nebula.enable {
          extra-substituters = [ "http://attic.${config.ogygia.domain}/nixos" ];
          extra-trusted-public-keys = [ "nixos:npaMjNtbUwWvuv4CEdJ2ev/Q2TRBxL0GduwvlYIc3/0=" ];
        })
      ];
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
        btop
        fd
        gh
        ghostty.terminfo
        git
        htop
        nix
        ogygia
        ripgrep
        tree
        vim

        (writeShellScriptBin "pastry" ''
          ${pkgs.pbcli}/bin/pbcli --host https://privatebin.${config.ogygia.domain} "$@" | ${pkgs.gnused}/bin/sed 's/privatebin.${config.ogygia.domain}/pastes.hillion.co.uk/g'
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
    services.caddy.package = pkgs.caddy-cloudflare;

    # Delegation
    custom.auto_updater.enable = true;
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
