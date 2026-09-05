# Automatic mounting of removable USB drives.
#
# Enabling this lets a graphical user just plug a drive in and have it mounted
# (and later unmounted on removal) without reaching for the terminal. It is
# deliberately desktop-agnostic: rather than living inside a specific window
# manager's module, it pairs the system-level udisks2 daemon with a
# udiskie session daemon running as a home-manager user service. That works
# under any WM (sway, awesome, ...) regardless of whether a file manager is
# installed.
{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.custom.desktop.automount;
in
{
  options.custom.desktop.automount = {
    enable = lib.mkEnableOption "automatic mounting of removable USB drives via udisks2 + udiskie";
  };

  config = lib.mkIf cfg.enable {
    # The udisks daemon exposes the D-Bus device/mount API that automount
    # agents (udiskie) and file managers call to mount/unmount removable media
    # and to be notified of device insertion/removal.
    services.udisks2.enable = true;

    # udiskie is a user-session daemon that mounts removable drives as they
    # are plugged in and unmounts them again when they are removed, with
    # desktop notifications and a tray icon (shown only when a tray is
    # present). Binding it to the graphical user's session target keeps it
    # WM-agnostic while matching the sway user-service pattern already used by
    # timewall.
    home-manager.users.${config.custom.user} = {
      systemd.user.services.udiskie = {
        Unit = {
          Description = "Automatic mounting of removable drives";
        };

        Service = {
          ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --notify --smart-tray";
          Restart = "on-failure";
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
