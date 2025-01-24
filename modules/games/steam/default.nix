{ config, lib, ... }:

let
  cfg = config.custom.games.steam;
in
{
  options.custom.games.steam = {
    enable = lib.mkEnableOption "steam";
  };

  config = lib.mkIf cfg.enable {
    programs.steam.enable = true;
  };
}
