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

    age.secrets."claude/context7-api-key" = {
      rekeyFile = ./context7-api-key.age;
      owner = user;
      mode = "0400";
    };

    home-manager.users.${user} = {
      # Deploy skills
      home.file.".claude/skills/jj/SKILL.md".source = ./jj-skill/SKILL.md;
      home.file.".claude/skills/commit/SKILL.md".source = ./commit-skill/SKILL.md;
      home.file.".claude/skills/github-fetch/SKILL.md".source = ./github-fetch-skill/SKILL.md;

      # Deploy settings with hooks configuration
      home.file.".claude/settings.json".text = builtins.toJSON claudeSettings;

      # Merge Context7 MCP server into ~/.claude.json at activation time
      home.activation.claude-mcp-servers = ''
        apiKey=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.age.secrets."claude/context7-api-key".path})
        target="$HOME/.claude.json"
        [ -L "$target" ] && target=$(${pkgs.coreutils}/bin/readlink -f "$target")
        [ -f "$target" ] || echo '{}' > "$target"

        ${pkgs.jq}/bin/jq \
          --arg key "$apiKey" \
          '.mcpServers.context7 = {
            "type": "http",
            "url": "https://mcp.context7.com/mcp",
            "headers": { "CONTEXT7_API_KEY": $key }
          }' "$target" > "$target.tmp"
        ${pkgs.coreutils}/bin/mv "$target.tmp" "$target"
      '';

      # Disable zoxide cd hook inside Claude Code subshells to avoid cd breakage.
      # Claude Code sets CLAUDECODE=1 in all subprocesses it spawns (Bash tool,
      # hooks, MCP, etc.), so we check for that and strip the cd function back out
      # after zoxide loads unconditionally (mkAfter ensures this runs after zoxide init).
      programs.zsh.initContent = lib.mkAfter ''
        if [[ -n "$CLAUDECODE" ]]; then
          unfunction cd 2>/dev/null || true
        fi
      '';
    };
  };
}
