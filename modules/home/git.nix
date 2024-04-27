{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.git;
in
{
  options.custom.home.git = {
    enable = lib.mkEnableOption "git";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.jake.programs.git = lib.mkIf (config.custom.user == "jake") {
      enable = true;
      extraConfig = {
        user = {
          email = "jake@hillion.co.uk";
          name = "Jake Hillion";
        };
        pull = {
          rebase = true;
        };
        merge = {
          conflictstyle = "diff3";
        };
        init = {
          defaultBranch = "main";
        };
      };
    };
  };
}
