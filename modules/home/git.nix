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
      home.packages = with pkgs; [ git-branchless jujutsu ];

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

        jujutsu = lib.mkIf (config.custom.user == "jake") {
          enable = true;
          settings = {
            user = {
              name = "Jake Hillion";
              email = "jake@hillion.co.uk";
            };
            templates = {
              git_push_bookmark = "\"jj/\" ++ change_id.short()";
            };
            ui = {
              default-command = "log";
              pager = "${lib.getExe pkgs.less} -FRX";
            };
            aliases = {
              submit-stack = [ "git" "push" "--change" "trunk()..@-" ];
              newt = [ "util" "exec" "--" "bash" "-c" "jj git fetch && jj new 'trunk()'" "" ];
              rpull = [ "util" "exec" "--" "bash" "-c" "jj git fetch && jj rebase -d 'trunk()'" ];
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
