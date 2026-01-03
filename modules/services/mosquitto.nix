{ config, lib, ... }:

let
  cfg = config.custom.services.mosquitto;
in
{
  options.custom.services.mosquitto = {
    enable = lib.mkEnableOption "mosquitto MQTT broker";
  };

  config = lib.mkIf cfg.enable {

    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = config.custom.dns.nebula.ipv4;
          port = 1883;
          users = {
            zigbee2mqtt = {
              acl = [ "readwrite #" ];
              hashedPassword = "$7$101$ZrD6C+b7Xo/fUoGw$Cf/6Xm52Syv2G+5+BqpUWRs+zrTrTvBL9EFzks9q/Q6ZggXVcp+Bi3ZpmQT5Du9+42G30Y7G3hWpYbA8j1ooWg==";
            };
            homeassistant = {
              acl = [ "readwrite #" ];
              hashedPassword = "$7$101$wGQZPdVdeW7iQFmH$bK/VOR6LXCLJKbb6M4PNeVptocjBAWXCLMtEU5fQNBr0Y5UAWlhVg8UAu4IkIXgnViI51NnhXKykdlWF63VkVQ==";
            };
            hearthd = {
              acl = [ "readwrite #" ];
              hashedPassword = "$7$101$zLBwMViF1og2s1kE$pXDLn4Z7Kta8/iItuJCXGpzqwqjSomzUxoUwSTV1zj26Sr2pRdNCbJMov6wlIk8MO3Ia8lUSHBxf/ss9QrjIkw==";
            };
          };
        }
      ];
    };

  };
}
