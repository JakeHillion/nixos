{ config, lib, ... }:

let
  cfg = config.custom.services.ntfy;
in
{
  options.custom.services.ntfy = {
    enable = lib.mkEnableOption "ntfy";
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        listen-http = "127.0.0.1:2586";
        base-url = "https://ntfy.hillion.co.uk";
      };
    };
  };
}
