{ config, pkgs, lib, ... }:

let
  cfg = config.custom.networking.l2tp;

  pppOptions = "/run/xl2tpd/${cfg.ifname}.options";

  # IPv4 is negotiated so the LNS accepts the session, but nothing is ever
  # routed over it: drop the peer route pppd installs as soon as IPCP is up.
  ipUp = pkgs.writeShellScript "l2tp-ip-up" ''
    ${pkgs.iproute2}/bin/ip -4 route flush dev ${lib.strings.escapeShellArg cfg.ifname}
  '';

  ipv6Up = pkgs.writeShellScript "l2tp-ipv6-up" ''
    ${pkgs.iproute2}/bin/ip -6 route replace default dev ${lib.strings.escapeShellArg cfg.ifname}
    ${lib.strings.optionalString (cfg.delegatedPrefix != null) ''
      # Traffic for unassigned parts of the delegation would otherwise follow
      # the default route straight back up the tunnel.
      ${pkgs.iproute2}/bin/ip -6 route replace unreachable ${cfg.delegatedPrefix}
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
    enable = lib.mkEnableOption "an L2TP (no IPsec) uplink used for IPv6 only";

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
