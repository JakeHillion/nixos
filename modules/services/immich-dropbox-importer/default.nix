{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.immich-dropbox-importer;

  watchDir = "${config.custom.syncthing.baseDir}/appdata/immich-dropbox";
  immichUrl = "https://immich.${config.ogygia.domain}";

  lifecycleScript = pkgs.writers.writePython3 "immich-dropbox-importer"
    {
      libraries = with pkgs.python3Packages; [ inotify-simple requests ];
    }
    (builtins.readFile ./immich-dropbox-importer.py);

in
{
  options.custom.services.immich-dropbox-importer = {
    enable = lib.mkEnableOption "Immich drop box import lifecycle management";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."immich-dropbox-importer/immich-api-key".file = ./immich-api-key.age;

    systemd.services.immich-dropbox-importer = {
      description = "Immich drop box import lifecycle management";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = [ pkgs.unstable.immich-cli pkgs.systemd ];

      serviceConfig = {
        ExecStart = lifecycleScript;
        Restart = "always";
        RestartSec = "300s";
        User = "jake";
        Group = "users";
        LoadCredential = [
          "immich-api-key:${config.age.secrets."immich-dropbox-importer/immich-api-key".path}"
        ];
      };

      environment = {
        WATCH_DIR = watchDir;
        IMMICH_URL = immichUrl;
        IMMICH_API_KEY_FILE = "%d/immich-api-key";
      };
    };

  };
}
