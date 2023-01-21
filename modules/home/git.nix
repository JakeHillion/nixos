{ pkgs, lib, config, ... }:

{
  home-manager.users.jake.programs.git = {
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
}
