{ pkgs, nixpkgs-unstable, lib, config, agenix-rekey, ... }:

{
  options.custom.defaults = lib.mkEnableOption "defaults";

  config = lib.mkIf config.custom.defaults {
    hardware.enableAllFirmware = true;
    nix = {
      settings = {
        auto-optimise-store = true;
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ config.custom.user ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 90d";
      };
    };
    nixpkgs.config.allowUnfree = true;

    time.timeZone = lib.mkDefault "Europe/London";
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
        agenix-rekey.packages."${system}".default
        btop
        fd
        gh
        ghostty.terminfo
        git
        htop
        nix
        nix-output-monitor
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

    # Caddy package with DNS plugins (cloudflare + jakehillion)
    services.caddy.package = pkgs.caddy-with-dns;

    # Delegation
    # Journal upload to central log server
    services.journald.upload = {
      enable = true;
      settings.Upload.URL = "http://${config.custom.locations.locations.services.journal_remote}:19532";
    };
    systemd.services.systemd-journal-upload = {
      after = [ "nebula-online@jakehillion.service" ];
      requires = [ "nebula-online@jakehillion.service" ];
    };

    custom.auto_updater.enable = true;
    custom.ca.consumer.enable = true;
    custom.compressed_ram.enable = true;
    custom.dns.enable = true;
    custom.home.defaults = true;
    custom.hostinfo.enable = true;
    custom.locations.autoServe = true;
    custom.nebula.enable = true;
    custom.ogygia.enable = true;
    custom.prometheus.client.enable = true;
    custom.shell.enable = true;
    custom.ssh.enable = true;
  };
}
