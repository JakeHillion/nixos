{ pkgs, lib, config, ... }:
let
  cfg = config.custom.home.claude;
  user = config.custom.user;

  claudeSettings = {
    enabledPlugins = {
      "rust-analyzer-lsp@claude-plugins-official" = true;
    };
    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${pkgs.opencode-plugin}/bin/claude-hook-shim";
            }
          ];
        }
        {
          matcher = "WebFetch";
          hooks = [
            {
              type = "command";
              command = "${pkgs.opencode-plugin}/bin/claude-webfetch-hook-shim";
            }
          ];
        }
      ];
    };
  };
in
{
  options.custom.home.claude = {
    enable = lib.mkEnableOption "Claude Code setup with skills and hooks";
  };

  config = lib.mkIf cfg.enable {
    custom.impermanence = lib.mkIf config.custom.impermanence.enable {
      userExtraFiles.${user} = [ ".claude.json" ];
      userExtraDirs.${user} = [ ".claude" ];
    };

    home-manager.users.${user} = {
      # Deploy skills
      home.file.".claude/skills/jj/SKILL.md".source = ./jj-skill/SKILL.md;
      home.file.".claude/skills/commit/SKILL.md".source = ./commit-skill/SKILL.md;
      home.file.".claude/skills/github-fetch/SKILL.md".source = ./github-fetch-skill/SKILL.md;

      # Deploy settings with hooks configuration
      home.file.".claude/settings.json".text = builtins.toJSON claudeSettings;
    };
  };
}
