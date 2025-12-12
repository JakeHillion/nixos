{ lib, config, ... }:

let
  cfg = config.custom.profiles.laptop;
in
{
  options.custom.profiles.laptop = lib.mkEnableOption "laptop profile";

  config = lib.mkIf cfg {
    # Enable automatic timezone detection based on GeoClue location
    # This uses the same GeoClue service that timewall uses for wallpapers
    services.automatic-timezoned.enable = lib.mkDefault true;
  };
}
