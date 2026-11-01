{ config, pkgs, lib, ... }:

let
  cfg = config.custom.networking.l2tp;

  pppOptions = "/run/xl2tpd/${cfg.ifname}.options";

  ip = "${pkgs.iproute2}/bin/ip";
  ifname = lib.strings.escapeShellArg cfg.ifname;
  uplink = lib.strings.escapeShellArg cfg.ipv4.uplinkInterface;

  resolveLns = ''
    lns=$(${pkgs.getent}/bin/getent ahostsv4 ${lib.strings.escapeShellArg cfg.server} | ${pkgs.gawk}/bin/awk 'NR == 1 { print $1 }')
  '';

  ipUp =
    if cfg.ipv4.enable then
    # The tunnel runs over the uplink, so once the default route moves into
    # the tunnel the LNS must stay reachable via the uplink's gateway.
      pkgs.writeShellScript "l2tp-ip-up" ''
        ${resolveLns}
        gateway=$(${ip} -4 route show default dev ${uplink} | ${pkgs.gawk}/bin/awk '$2 == "via" { print $3; exit }')
        if [ -z "$lns" ] || [ -z "$gateway" ]; then
          echo "no route to the LNS via ${cfg.ipv4.uplinkInterface}, not routing IPv4" >&2
          exit 0
        fi
        ${ip} -4 route replace "$lns/32" via "$gateway" dev ${uplink}
        ${ip} -4 route replace default dev ${ifname} metric ${toString cfg.ipv4.metric}
      ''
    else
    # IPv4 is negotiated so the LNS accepts the session, but nothing is ever
    # routed over it: drop the peer route pppd installs as soon as IPCP is up.
      pkgs.writeShellScript "l2tp-ip-up" ''
        ${ip} -4 route flush dev ${ifname}
      '';

  # Drop the LNS host route so a redial follows the uplink's current gateway.
  ipDown = pkgs.writeShellScript "l2tp-ip-down" ''
    ${resolveLns}
    if [ -n "$lns" ]; then
      ${ip} -4 route del "$lns/32" dev ${uplink} || true
    fi
  '';

  ipv6Up = pkgs.writeShellScript "l2tp-ipv6-up" ''
    ${ip} -6 route replace default dev ${ifname}
    ${lib.strings.optionalString (cfg.delegatedPrefix != null) ''
      # Traffic for unassigned parts of the delegation would otherwise follow
      # the default route straight back up the tunnel.
      ${ip} -6 route replace unreachable ${cfg.delegatedPrefix}
    ''}
  '';

  xl2tpdConf = pkgs.writeText "xl2tpd.conf" ''
    [lac ${cfg.ifname}]
    lns = ${cfg.server}
    autodial = yes
    redial = yes
    redial timeout = 15
    length bit = yes
    pppoptfile = ${pppOptions}
  '';
in
{
  options.custom.networking.l2tp = {
    enable = lib.mkEnableOption "an L2TP (no IPsec) uplink";

    server = lib.mkOption {
      type = lib.types.str;
      description = "Hostname or address of the LNS.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      description = "PPP username.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the PPP password.";
    };

    ifname = lib.mkOption {
      type = lib.types.str;
      default = "l2tp";
      description = "Name of the PPP interface.";
    };

    mtu = lib.mkOption {
      type = lib.types.int;
      default = 1460;
      description = "PPP MTU/MRU. Leaves room for IPv4, UDP, L2TP and PPP headers inside a 1500 byte WAN.";
    };

    ipv4 = {
      enable = lib.mkEnableOption "routing IPv4 over the tunnel. Without it only IPv6 is routed";

      uplinkInterface = lib.mkOption {
        type = lib.types.str;
        description = "Interface the tunnel itself runs over. The LNS is pinned to this interface's default gateway.";
      };

      metric = lib.mkOption {
        type = lib.types.int;
        default = 512;
        description = "Metric of the IPv4 default route via the tunnel. Must beat the uplink's own default route.";
      };
    };

    delegatedPrefix = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "2001:db8:1234::/48";
      description = ''
        Prefix delegated over DHCPv6-PD. It is requested (with this as a hint) but not assigned to
        any interface; subnets are assigned statically. An unreachable route
        covers the whole prefix.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "l2tp_ppp" ];

    systemd.services.xl2tpd = {
      description = "L2TP uplink via ${cfg.server}";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      path = [ pkgs.coreutils pkgs.gnused ];

      preStart = ''
        password=$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' ${lib.strings.escapeShellArg cfg.passwordFile})
        install -m 600 /dev/stdin ${pppOptions} <<EOF
        user "${cfg.username}"
        password "$password"
        ifname ${cfg.ifname}
        noauth
        noipdefault
        nodefaultroute
        +ipv6
        nodefaultroute6
        noccp
        mtu ${toString cfg.mtu}
        mru ${toString cfg.mtu}
        lcp-echo-interval 10
        lcp-echo-failure 6
        ip-up-script ${ipUp}
        ${lib.strings.optionalString cfg.ipv4.enable "ip-down-script ${ipDown}"}
        ipv6-up-script ${ipv6Up}
        EOF
      '';

      serviceConfig = {
        ExecStart = "${pkgs.xl2tpd}/bin/xl2tpd -D -c ${xl2tpdConf} -s ${pkgs.emptyFile} -p /run/xl2tpd/xl2tpd.pid -C /run/xl2tpd/l2tp-control";
        RuntimeDirectory = "xl2tpd";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = "15s";
      };
    };

    networking.dhcpcd = {
      allowInterfaces = [ cfg.ifname ];
      extraConfig = ''
        interface ${cfg.ifname}
          noipv4
          noipv6rs
          nohook resolv.conf
          ia_na 1
          ${lib.strings.optionalString (cfg.delegatedPrefix != null) "ia_pd 2/${cfg.delegatedPrefix} -"}
      '';
    };
  };
}
