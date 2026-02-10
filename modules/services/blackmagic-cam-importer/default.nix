{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.blackmagic-cam-importer;

  watchDir = "${config.custom.syncthing.baseDir}/appdata/blackmagic-cam";
  immichUrl = "https://immich.${config.ogygia.domain}";

  lifecycleScript = pkgs.writers.writePython3 "blackmagic-cam-importer"
    {
      libraries = with pkgs.python3Packages; [ inotify-simple requests ];
    }
    (builtins.readFile ./blackmagic-cam-importer.py);

in
{
  options.custom.services.blackmagic-cam-importer = {
    enable = lib.mkEnableOption "blackmagic camera video lifecycle management";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."blackmagic-cam-importer/immich-api-key".file = ./immich-api-key.age;

    systemd.services.blackmagic-cam-importer = {
      description = "Blackmagic camera video lifecycle management";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = [ pkgs.immich-cli pkgs.systemd ];

      serviceConfig = {
        ExecStart = lifecycleScript;
        Restart = "always";
        RestartSec = "300s";
        User = "jake";
        Group = "users";
        LoadCredential = [
          "immich-api-key:${config.age.secrets."blackmagic-cam-importer/immich-api-key".path}"
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
