{ config, lib, ... }:

let
  cfg = config.custom.services.tangled_appview;
  locations = config.custom.locations.locations;
in
{
  options.custom.services.tangled_appview = {
    enable = lib.mkEnableOption "tangled appview";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "tangled.hillion.co.uk";
    };

    environmentSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the age-encrypted environment file containing TANGLED_COOKIE_SECRET, TANGLED_OAUTH_CLIENT_SECRET, etc.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."tangled/appview/env" = lib.mkIf (cfg.environmentSecretFile != null) {
      file = cfg.environmentSecretFile;
    };

    services.tangled.appview = {
      enable = true;
      port = cfg.port;
      appviewHost = "https://${cfg.domain}";
      appviewName = "Hillion Tangled";

      dbPath = lib.mkIf config.custom.impermanence.enable
        "${config.custom.impermanence.base}/system/var/lib/appview/appview.db";

      environmentFile = lib.mkIf (cfg.environmentSecretFile != null)
        config.age.secrets."tangled/appview/env".path;
    };

    systemd.services.appview.serviceConfig.ReadWritePaths = lib.mkIf config.custom.impermanence.enable [
      "${config.custom.impermanence.base}/system/var/lib/appview"
    ];
  };
}
