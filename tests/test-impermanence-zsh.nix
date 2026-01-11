# Test ZSH history path with impermanence
{ testLib, lib, ... }:

let
  inherit (testLib) evalConfig;

  config = evalConfig {
    modules = [{
      custom.impermanence.enable = true;
    }];
  };

in
{
  home-manager.users.jake.programs.zsh.history.path = config.config.home-manager.users.jake.programs.zsh.history.path;
  home-manager.users.root.programs.zsh.history.path = config.config.home-manager.users.root.programs.zsh.history.path;
}
