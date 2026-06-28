{ config, lib, ... }:

let
  cfg = config.custom.games.steam;
in
{
  options.custom.games.steam = {
    enable = lib.mkEnableOption "steam";
  };

  config = lib.mkIf cfg.enable {
    programs.steam.enable = true;

    # Raise the soft open-file limit from systemd's 1024 default. Steam + Proton
    # (and the impermanence bindfs mount backing ~/.local/share/Steam, which is a
    # systemd unit and inherits the same 1024) exhaust it when loading a game's
    # DLLs and .big archives, making Wine fail with "Too many open files" so the
    # game exits instantly. Lift the soft limit to the existing hard cap for
    # systemd-managed units and PAM login sessions alike.
    systemd.settings.Manager.DefaultLimitNOFILE = "524288:524288";
    systemd.user.extraConfig = "DefaultLimitNOFILE=524288:524288";
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "-";
        item = "nofile";
        value = "524288";
      }
    ];

    # Persist Steam data when using impermanence
    custom.impermanence.userExtraDirs.${config.custom.user} = lib.lists.optional config.custom.impermanence.enable ".local/share/Steam";
  };
}
