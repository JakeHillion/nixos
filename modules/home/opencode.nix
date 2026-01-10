{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.opencode;
  user = config.custom.user;
in
{
  options.custom.home.opencode.enable = lib.mkEnableOption "OpenCode setup";

  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      home.packages = [ pkgs.unstable.opencode ];
    };

    custom.impermanence.users.${user}.directories = lib.mkIf config.custom.impermanence.enable [
      ".local/share/opencode"
    ];
  };
}
