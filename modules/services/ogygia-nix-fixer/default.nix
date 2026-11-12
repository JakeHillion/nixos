{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.ogygia-nix-fixer;
  user = "ogygia-nix-fixer";
  home = "/var/lib/${user}";
  repo = "${home}/repo";
  fuzzData = config.custom.services.ogygia-nix-eval-fuzz.dataDir;
  runtime = "/run/${user}";
  pi = pkgs.unstable.pi-coding-agent;
  journal = pkgs.writeText "${user}-journal.ts" (lib.replaceStrings
    [ "@systemd-cat@" ] [ "${pkgs.systemd}/bin/systemd-cat" ]
    (builtins.readFile ./journal.ts));
  settings = pkgs.writeText "${user}-settings.json" (builtins.toJSON {
    defaultProvider = "openai";
    defaultModel = "gpt-6.1-sol";
    defaultThinkingLevel = "high";
    enabledModels = [ "openai/gpt-6.1-sol" ];
    defaultProjectTrust = "always";
    enableInstallTelemetry = false;
    lastChangelogVersion = pi.version;
    skills = [ "${repo}/.claude/skills" ];
  });
  jjConfig = pkgs.writeText "${user}-jj.toml" ''
    [user]
    name = "Jake Hillion"
    email = "jake@hillion.co.uk"
  '';
  prompt = pkgs.writeText "${user}-prompt" ''
    Run the existing fuzz-fix-loop skill in this checkout. Read AGENTS.md,
    CONTRIBUTING.md, .git-commit-template, .claude/skills/fuzz-fix-loop/SKILL.md
    and .claude/skills/fix-fuzz-finding/SKILL.md before beginning.
    Paths in those skills are relative to this repository, not the skill directory.

    DIR=${home}/fuzzing; STATE=${home}/state. The tracking document is
    STATE/tracking.md: read it before beginning and keep it up to date as the
    fuzz-fix-loop skill describes. Report anything requiring a decision in
    this conversation.
    On the first run, start fresh on trunk(): no old megamerge, substacks,
    Claude conversation or loop state is to be imported. On subsequent starts,
    inspect and reuse STATE/megamerge and the existing working copy; never
    discard unfinished changes just to restart the loop.

    Schedules and workers belong to this Pi process, not the saved transcript.
    After a restart, list live loops/jobs and start a new loop as needed; IDs
    from an earlier process are no longer valid. The checkout and STATE remain.
    Use the installed generic loop skill and loop/schedule_wakeup tools for
    self-paced ticks. Reuse the live loop ID when replacing a fallback timer.
    Use a fresh worker subagent for each fix and a separate fresh worker for
    placement, with background=true so this conversation stays interactive.
    Only one worker may write to the checkout at a time; completion wakes this
    session. Use a timeout for triage as the skill permits, not an untracked
    background shell. Don't block this session with a long sleep.

    Follow the skills' clean-room, testing and commit-placement rules. Never
    edit or delete findings, run recheck, start fuzzing, push, or open PRs.
    This session already runs inside the repository's dev shell. Keep your
    own state under STATE.
    If the user takes over, cancel the loop
    and stop any worker before handing back the checkout.
  '';
  tmuxConfig = pkgs.writeText "${user}-tmux.conf" ''
    set -g default-shell ${lib.getExe pkgs.bash}
    set -g prefix None
    set -g prefix2 None
    unbind-key -a
    unbind-key -a -T root
    set -g status off
    set -g mouse off
    set -g set-titles off
    set -g update-environment ""
    set -g default-terminal tmux-256color
    set -g extended-keys on
    set -g extended-keys-format csi-u
    set -as terminal-features ",*:extkeys"
    set -g window-size latest
  '';
  launch = pkgs.writeShellScript "${user}-pi" ''
    exec nix develop ${repo} --command ${lib.getExe pi} \
      --session-id coordinator --name fuzz-fix-loop "$(< ${prompt})"
  '';
in
{
  options.custom.services.ogygia-nix-fixer.enable = lib.mkEnableOption "interactive Pi fuzz-finding handler";

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.custom.services.ogygia-nix-eval-fuzz.enable;
      message = "The fuzz fixer needs the local ogygia-nix-eval-fuzz data directory.";
    }];

    users.users.${user} = {
      uid = config.ids.uids.${user};
      group = user;
      isSystemUser = true;
      inherit home;
    };
    users.groups.${user}.gid = config.ids.gids.${user};
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ home ];
    environment.systemPackages = [ pkgs.tmux ];

    systemd.services.${user} = {
      description = "Interactive Pi handler for ogygia-nix fuzzer findings";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "ogygia-nix-eval-fuzz.service" ];
      environment = {
        HOME = home;
        PI_SKIP_VERSION_CHECK = "1";
        PI_TELEMETRY = "0";
        GIT_TERMINAL_PROMPT = "0";
      };
      path = with pkgs; [ pi unstable.jujutsu git nix coreutils bash ripgrep findutils gnugrep gnused gawk curl cacert tmux xxd python3 diffutils patch jq file procps util-linux less tree gnutar gzip which ];
      preStart = ''
        install -d -m 0700 ${home}/.pi/agent ${home}/.config/jj
        install -d ${home}/.pi/agent/{extensions,agents,skills} ${home}/state
        # Seed mutable settings, rather than making Pi's runtime state a store link.
        if [ ! -e ${home}/.pi/agent/settings.json ]; then
          install -m 0600 ${settings} ${home}/.pi/agent/settings.json
        fi
        ln -sfn ${jjConfig} ${home}/.config/jj/config.toml
        ln -sfn ${pkgs.piPackages.background-subagents} ${home}/.pi/agent/extensions/subagent
        ln -sfn ${pkgs.piPackages.loop} ${home}/.pi/agent/extensions/loop
        ln -sfn ${journal} ${home}/.pi/agent/extensions/journal.ts
        ln -sfn ${pkgs.piPackages.loop}/skills/loop ${home}/.pi/agent/skills/loop
        ln -sfn ${../../home/pi/agents/worker.md} ${home}/.pi/agent/agents/worker.md
        if [ ! -d ${repo}/.jj ]; then
          jj git clone --colocate https://github.com/ogygia-nix/ogygia-nix.git ${repo}
        fi
      '';
      script = ''
        tmux -S ${runtime}/tmux.sock -f ${tmuxConfig} \
          new-session -d -s fixer -c ${repo} ${launch}
        tmux -S ${runtime}/tmux.sock display-message -p '#{pid}' > ${runtime}/tmux.pid
      '';
      serviceConfig = {
        Type = "forking";
        PIDFile = "${runtime}/tmux.pid";
        User = user;
        Group = user;
        SupplementaryGroups = [ "ogygia-nix-eval-fuzz" ];
        StateDirectory = user;
        StateDirectoryMode = "0750";
        RuntimeDirectory = user;
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = home;
        UMask = "0027";
        BindReadOnlyPaths = [ "${fuzzData}:${home}/fuzzing" ];
        ReadOnlyPaths = [ fuzzData ] ++ lib.optional config.custom.impermanence.enable
          "${config.custom.impermanence.base}/system${fuzzData}";
        UnsetEnvironment = [ "SSH_AUTH_SOCK" "GH_TOKEN" "GITHUB_TOKEN" ];
        NoNewPrivileges = true;
        Restart = "always";
        RestartSec = "30s";
        TimeoutStartSec = "15min";
        TimeoutStopSec = "30s";
      };
    };
  };
}
