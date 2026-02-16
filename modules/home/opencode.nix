{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.opencode;
  user = config.custom.user;

  opencodeConfig = {
    plugin = [
      "file://${pkgs.opencode-plugin}/lib/opencode-plugin/dist/src/index.js"
    ];
  };
in
{
  options.custom.home.opencode.enable = lib.mkEnableOption "OpenCode setup";

  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      home.packages = [ pkgs.unstable.opencode ];

      # Deploy OpenCode config with plugin reference
      xdg.configFile."opencode/opencode.json".text = builtins.toJSON opencodeConfig;
    };

    custom.impermanence = lib.mkIf config.custom.impermanence.enable {
      userExtraDirs.${user} = [ ".local/share/opencode" ];
    };
  };
}
