{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.git;

  jj-update-prs = pkgs.writers.writePython3Bin "jj-update-prs"
    {
      libraries = [ pkgs.python3Packages.pyyaml ];
    }
    (builtins.readFile ./jj-update-prs.py);
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
            revset-aliases = {
              "immutable_heads()" = ''builtin_immutable_heads() ~ remote_bookmarks(exact:"ogygia/deployed-commits-archive")'';
            };
            aliases = {
              submit-stack = [ "git" "push" "--change" "trunk()..@-" ];
              update-prs = [ "util" "exec" "--" "${jj-update-prs}/bin/jj-update-prs" ];
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
