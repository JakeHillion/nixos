{ config, lib, ... }:

{
  options.custom.services.dancefloor = {
    enable = lib.mkEnableOption "dancefloor control server";
  };

  config = lib.mkIf config.custom.services.dancefloor.enable {
    services.dancefloor-server = {
      enable = true;

      # Reached over Nebula by the public vhost in modules/www/global.nix, so
      # there is nothing to gain from listening anywhere else. neb.ogygia is a
      # trusted interface, so no port needs opening.
      address = config.custom.dns.nebula.ipv4;
      port = 8080;
    };

    systemd.services.dancefloor-server = {
      after = [ "nebula-online@ogygia.service" ];
      requires = [ "nebula-online@ogygia.service" ];
    };

    # DynamicUser, so StateDirectory=dancefloor lands in /var/lib/private.
    custom.impermanence.extraDirs =
      lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/dancefloor" ];
  };
}
