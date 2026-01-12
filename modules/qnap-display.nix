{ config, pkgs, lib, ... }:

let
  cfg = config.custom.qnap-display;

  # Extract short hostname: hostname + first part of domain
  # e.g., "sundown" + "st" from "sundown.st.neb.jakehillion.me"
  shortHostname =
    let
      domainParts = lib.splitString "." config.networking.domain;
      firstDomainPart = lib.head domainParts;
    in
    "${config.networking.hostName}.${firstDomainPart}";

  lcd-display = pkgs.writers.writePython3 "qnap-lcd-display"
    {
      libraries = [ pkgs.qnaplcd pkgs.python3Packages.humanize ];
    } ''
    import json
    import sys
    import time
    import qnaplcd
    import threading
    import subprocess
    import humanize
    from pathlib import Path
    from datetime import datetime

    DISPLAY_TIMEOUT = 30  # seconds
    PORT = '/dev/ttyS1'
    PORT_SPEED = 1200
    HOSTNAME = "${shortHostname}"
    FLAKE_URL = "git+https://gitea.hillion.co.uk/JakeHillion/nixos"

    lcd = None
    lcd_timer = None


    def lcd_on():
        global lcd_timer
        lcd.backlight(True)
        if lcd_timer:
            lcd_timer.cancel()
        lcd_timer = threading.Timer(DISPLAY_TIMEOUT, lambda: lcd.backlight(False))
        lcd_timer.start()


    def get_commit_date(revision):
        """Get commit date from Nix flake metadata"""
        cmd = [
            'nix', 'flake', 'metadata', '--json',
            f'{FLAKE_URL}?rev={revision}'
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            err = f"Nix flake metadata failed: {result.returncode}"
            print(f"{err}\nstdout: {result.stdout}", file=sys.stderr)
            print(f"stderr: {result.stderr}", file=sys.stderr)
            return None

        data = json.loads(result.stdout)
        timestamp = data.get('lastModified')
        if timestamp:
            return datetime.fromtimestamp(timestamp)
        return None


    def read_build_info():
        """Read build revision and date from Nix flake metadata"""
        build_file = Path("/run/current-system/sw/share/ogygia/build-revision")

        try:
            revision = build_file.read_text().strip()
        except Exception as e:
            print(f"Error reading build-revision file: {e}", file=sys.stderr)
            return "unknown", None

        short_hash = revision[:7] if len(revision) >= 7 else revision

        try:
            commit_date = get_commit_date(revision)
        except Exception as e:
            print(f"Error getting commit date: {e}", file=sys.stderr)
            commit_date = None

        return short_hash, commit_date


    def format_relative_time(commit_date):
        """Format commit date as relative time using humanize"""
        if commit_date is None:
            return "unknown"

        try:
            now = datetime.now()
            delta = now - commit_date

            # Use humanize.precisedelta for more control
            # minimum_unit='minutes' to avoid showing seconds
            relative = humanize.precisedelta(
                delta,
                minimum_unit='minutes',
                format='%0.0f'
            )
            return relative
        except Exception as e:
            print(f"Error formatting time: {e}", file=sys.stderr)
            return "unknown"


    def show_hostname():
        short_hash, commit_date = read_build_info()
        relative_time = format_relative_time(commit_date)
        lcd.clear()
        lcd.write(0, [HOSTNAME, f"{short_hash} {relative_time}"])


    def show_uptime():
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])

        days = int(uptime_seconds // 86400)
        hours = int((uptime_seconds % 86400) // 3600)
        minutes = int((uptime_seconds % 3600) // 60)

        if days > 0:
            uptime_str = f"{days}d {hours}h {minutes}m"
        else:
            uptime_str = f"{hours}h {minutes}m"

        with open('/proc/loadavg', 'r') as f:
            load_parts = f.readline().split()
            load = f"{load_parts[0]} {load_parts[1]}"

        lcd.clear()
        lcd.write(0, [f"Up: {uptime_str}", f"Load: {load}"])


    # Menu
    menu_item = 0
    menu = [
        show_hostname,
        show_uptime
    ]


    def response_handler(command, data):
        global menu_item
        prev_menu = menu_item

        if command == 'Switch_Status':
            lcd_on()
            if data == 0x01:  # up
                menu_item = (menu_item - 1) % len(menu)
            if data == 0x02:  # down
                menu_item = (menu_item + 1) % len(menu)

        if prev_menu != menu_item:
            menu[menu_item]()


    def main():
        global lcd

        lcd = qnaplcd.QnapLCD(PORT, PORT_SPEED, response_handler)
        lcd_on()
        lcd.reset()
        lcd.clear()

        lcd.write(0, [HOSTNAME, "System Ready..."])

        time.sleep(3)

        # Main loop
        while True:
            menu[menu_item]()
            time.sleep(30)


    if __name__ == "__main__":
        main()
  '';
in
{
  options.custom.qnap-display = {
    enable = lib.mkEnableOption "QNAP LCD display service";

    port = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyS1";
      description = "Serial port for the LCD display";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.qnap-display = {
      description = "QNAP LCD Display Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = [ pkgs.nix ];

      serviceConfig = {
        ExecStart = "${lcd-display}";
        Restart = "always";
        RestartSec = "10s";

        # Security hardening
        DynamicUser = true;
        SupplementaryGroups = [ "dialout" ];

        # Allow access to serial port
        DeviceAllow = [ "${cfg.port} rw" ];
        DevicePolicy = "closed";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ "/run/current-system" ];
      };
    };

    # Ensure dialout group exists
    users.groups.dialout = { };
  };
}
