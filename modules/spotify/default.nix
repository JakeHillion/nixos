{ config, pkgs, lib, ... }:


{
  config.age.secrets."spotify/11132032266" = {
    file = ../../secrets/spotify/11132032266.age;
    owner = "jake";
  };

  config.hardware.pulseaudio.enable = true;

  config.users.users.jake.extraGroups = [ "audio" ];
  config.users.users.jake.packages = with pkgs; [ spotify-tui ];

  config.home-manager.users.jake.services.spotifyd = {
    enable = true;
    settings = {
      global = {
        username = "11132032266";
        password_cmd = "cat ${config.age.secrets."spotify/11132032266".path}";
        backend = "pulseaudio";
      };
    };
  };
}
