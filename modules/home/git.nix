{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.git;
in
{
  options.custom.home.git = {
    enable = lib.mkEnableOption "git";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.jake = {
      home.packages = with pkgs; [ git-branchless ];

      programs = {
        sapling = lib.mkIf (config.custom.user == "jake") {
          enable = true;
          userName = "Jake Hillion";
          userEmail = "jake@hillion.co.uk";

          extraConfig = {
            ui = {
              "merge:interactive" = ":merge3";
            };
          };
        };

        git = lib.mkIf (config.custom.user == "jake") {
          enable = true;

          settings = {
            user = {
              name = "Jake Hillion";
              email = "jake@hillion.co.uk";
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
    };
  };
}
