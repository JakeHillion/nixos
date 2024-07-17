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

      extraConfig = lib.strings.concatLines [
        (lib.readFile ./.tmux.conf)

        ''set -g status-right "${lib.strings.optionalString config.custom.laptop "#{battery_icon} #{battery_percentage} #{battery_remain} | "}\"#{=21:pane_title}\" %H:%M %d-%b-%y"''
      ];

      plugins = with pkgs; lib.lists.optional config.custom.laptop tmuxPlugins.battery;
    };
  };
}
