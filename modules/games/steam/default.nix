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

    # Persist Steam data when using impermanence
    custom.impermanence.users.${config.custom.user}.directories = lib.mkIf config.custom.impermanence.enable [
      ".local/share/Steam"
    ];
  };
}
