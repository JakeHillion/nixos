{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.ogygia-nix-fixer;
  user = config.custom.user;
  sourceHome = "/var/lib/ogygia-nix-fixer";
  destination =
    if config.custom.impermanence.enable
    then "${config.custom.impermanence.base}/users/${user}/repos/ogygia-nix-fuzz-review"
    else "${config.users.users.${user}.home}/repos/ogygia-nix-fuzz-review";
  importer = pkgs.writers.writePython3Bin "ogygia-nix-fixer-review" { }
    (builtins.readFile ./review.py);
in
{
  config = lib.mkIf cfg.enable {
    # Read the checkout/state, but not the private .pi/agent directory. The
    # service's read-only mounts also cover the impermanence backing path.
    users.groups.ogygia-nix-fixer.members = [ user ];

    systemd.services.ogygia-nix-fixer-review = {
      description = "Pull actionable fuzz fixes into ${user}'s review repository";
      after = [ "ogygia-nix-fixer.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.unstable.jujutsu ];
      environment = {
        HOME = config.users.users.${user}.home;
        GIT_TERMINAL_PROMPT = "0";
      };
      serviceConfig = {
        Type = "oneshot";
        User = user;
        UMask = "0027";
        NoNewPrivileges = true;
        ReadOnlyPaths = [ "-${sourceHome}" ] ++ lib.optional config.custom.impermanence.enable
          "-${config.custom.impermanence.base}/system${sourceHome}";
        ExecStart = "${lib.getExe importer} ${sourceHome}/repo ${destination} https://github.com/ogygia-nix/ogygia-nix.git";
        TimeoutStartSec = "15min";
      };
    };
    systemd.timers.ogygia-nix-fixer-review = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitInactiveSec = "5min";
      };
    };
  };
}
