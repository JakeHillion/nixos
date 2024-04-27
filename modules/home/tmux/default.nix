{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.tmux;
in
{
  options.custom.home.tmux = {
    enable = lib.mkEnableOption "tmux";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.jake.programs.tmux = {
      enable = true;
      extraConfig = lib.readFile ./.tmux.conf;
    };
  };
}
