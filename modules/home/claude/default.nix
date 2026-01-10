{ pkgs, lib, config, ... }:
let
  cfg = config.custom.home.claude;
  user = config.custom.user;
in
{
  options.custom.home.claude = {
    enable = lib.mkEnableOption "Claude Code setup with skills";
  };

  config = lib.mkIf cfg.enable {
    custom.impermanence.users.${user} = lib.mkIf config.custom.impermanence.enable {
      files = [ ".claude.json" ];
      directories = [ ".claude" ];
    };

    home-manager.users.${user} = {
      # Deploy skills to personal skills directory
      home.file.".claude/skills/nix/SKILL.md".source = ./nix-skill/SKILL.md;
      home.file.".claude/skills/jj/SKILL.md".source = ./jj-skill/SKILL.md;
      home.file.".claude/skills/commit/SKILL.md".source = ./commit-skill/SKILL.md;
    };
  };
}
