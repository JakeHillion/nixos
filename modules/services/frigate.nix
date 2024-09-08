{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.frigate;
in
{
  options.custom.services.frigate = {
    enable = lib.mkEnableOption "frigate";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."frigate/secrets.env".file = ../../secrets/frigate/secrets.env.age;

    services.frigate = {
      enable = true;
      hostname = "frigate.ts.hillion.co.uk";

      settings = {
        cameras = {
          living_room = {
            enabled = true;
            ffmpeg.inputs = [
              {
                path = "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@10.133.145.2:554/h264Preview_01_sub";
                roles = [ "detect" ];
              }
              {
                path = "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@10.133.145.2:554/";
                roles = [ "record" ];
              }
            ];
          };
        };
      };
    };
    systemd.services.frigate.unitConfig.EnvironmentFile = config.age.secrets."frigate/secrets.env".path;
  };
}
