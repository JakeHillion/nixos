{ config, pkgs, lib, ... }:

let
  # Server definitions with their Nebula IPs and PDU outlets
  servers = {
    phoenix_st = {
      name = "Phoenix ST";
      ip = config.custom.dns.authoritative.ipv4.me.jakehillion.neb.st.phoenix;
      outlet = 1;
    };
    rooster_cx = {
      name = "Rooster CX";
      ip = config.custom.dns.authoritative.ipv4.me.jakehillion.neb.cx.rooster;
      outlet = 2;
    };
    stinger_pop = {
      name = "Stinger POP";
      ip = config.custom.dns.authoritative.ipv4.me.jakehillion.neb.pop.stinger;
      outlet = 3;
    };
    warlock_cx = {
      name = "Warlock CX";
      ip = config.custom.dns.authoritative.ipv4.me.jakehillion.neb.cx.warlock;
      outlet = 4;
    };
    theon_storage = {
      name = "Theon Storage";
      ip = config.custom.dns.authoritative.ipv4.me.jakehillion.neb.storage.theon;
      outlet = 5;
    };
  };

  pduWrapper = pkgs.writeShellScript "pdu_control_wrapper" ''
    set -euo pipefail

    # Shell wrapper for PDU control that reads the password and calls the expect script
    # Usage: pdu_control_wrapper.sh <outlet_number> <on|off>

    if [ $# -ne 2 ]; then
        echo "Usage: $0 <outlet_number> <on|off>" >&2
        exit 1
    fi

    outlet_number="$1"
    action="$2"

    # Add inetutils to PATH for telnet command
    export PATH="${pkgs.inetutils}/bin:$PATH"

    # Call the expect script using expect directly
    exec ${pkgs.expect}/bin/expect ${./pdu_switch_control.expect} "$outlet_number" "$action" "$(cat ${config.age.secrets."homeassistant/pdu_password".path})"
  '';

in
{
  command_line = (lib.mapAttrsToList
    (serverId: server: {
      switch = {
        name = "Home AP7921 ${server.name}";
        command_on = "${pduWrapper} ${toString server.outlet} on";
        command_off = "${pduWrapper} ${toString server.outlet} off";
      };
    })
    servers) ++ (lib.mapAttrsToList
    (serverId: server: {
      binary_sensor = {
        name = "${lib.strings.stringAsChars (c: if c == " " then "_" else lib.strings.toLower c) server.name}_ping";
        device_class = "connectivity";
        command = "${pkgs.iputils}/bin/ping -c1 -W10 ${server.ip} >/dev/null 2>&1 && echo ON || echo OFF";
        scan_interval = 60;
        payload_on = "ON";
        payload_off = "OFF";
      };
    })
    servers);

  switch = [
    {
      name = "merlin.rig.${config.ogygia.domain}";
      platform = "wake_on_lan";
      mac = "b0:41:6f:13:20:14";
      host = "10.64.50.28";
    }
    {
      name = "maverick.cx.${config.ogygia.domain}";
      platform = "wake_on_lan";
      mac = "38:05:25:34:02:34";
      host = "10.64.50.26";
    }
  ];

  input_boolean = {
    merlin_boot_windows = {
      name = "Boot Merlin to Windows next startup";
      icon = "mdi:microsoft-windows";
    };
  };

}
