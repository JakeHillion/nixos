{ config, pkgs, lib, ... }:

let
  cfg = config.custom.networking.l2tp;

  pppOptions = "/run/xl2tpd/${cfg.ifname}.options";

  ip = "${pkgs.iproute2}/bin/ip";
  ifname = lib.strings.escapeShellArg cfg.ifname;

  # Without IPv4 enabled, IPv4 is negotiated so the LNS accepts the session,
  # but nothing is ever routed over it: drop the peer route pppd installs as
  # soon as IPCP is up.
  ipUp = pkgs.writeShellScript "l2tp-ip-up" ''
    ${ip} -4 route flush dev ${ifname}
  '';

  # pppd installs the IPv4 default once IPCP is up. A route configured when
  # the link appears is flushed by the kernel as pppd sets the peer address,
  # with no netlink notification, so networkd would never restore it. The LNS
  # keeps its own host route via the underlay, so the default can move into
  # the tunnel without the tunnel routing through itself.
  defaultRoute =
    if cfg.ipv4.enable then
      "defaultroute\ndefaultroute-metric ${toString cfg.ipv4.metric}"
    else
      "nodefaultroute";

  xl2tpdConf = pkgs.writeText "xl2tpd.conf" ''
    [lac ${cfg.ifname}]
    lns = ${cfg.server}
    autodial = yes
    redial = yes
    redial timeout = 15
    length bit = yes
    pppoptfile = ${pppOptions}
  '';

  # Seconds between probe rounds.
  interval = 5;
  # Consecutive failed rounds before moving the tunnel to the backup.
  failThreshold = 3;
  # Consecutive successful rounds before moving the tunnel back to the
  # primary. Larger than failThreshold so a flapping primary stays on the
  # backup.
  recoverThreshold = 12;

  underlayMonitor = pkgs.writeShellApplication {
    name = "l2tp-underlay";
    runtimeInputs = with pkgs; [ iproute2 iputils getent gawk systemd ];
    text = ''
      primary=${lib.strings.escapeShellArg cfg.underlay.primaryInterface}
      backup=${lib.strings.escapeShellArg cfg.underlay.backupInterface}
      backup_gateway=${lib.strings.escapeShellArg cfg.underlay.backupGateway}
      targets=(${lib.strings.escapeShellArgs cfg.underlay.targets})

      until lns=$(getent ahostsv4 ${lib.strings.escapeShellArg cfg.server} | awk 'NR == 1 { print $1 }') && [ -n "$lns" ]; do
        echo "waiting to resolve ${cfg.server}"
        sleep ${toString interval}
      done
      echo "LNS is $lns"

      # A round succeeds if any target answers via the primary. Pings are bound
      # to the primary so it is still probed while the tunnel runs over the
      # backup. Each round starts at the next target to spread load across them.
      probe() {
        local i
        for ((i = 0; i < ''${#targets[@]}; i++)); do
          if ping -n -q -c 1 -W 2 -I "$primary" "''${targets[(round + i) % ''${#targets[@]}]}" >/dev/null 2>&1; then
            return 0
          fi
        done
        return 1
      }

      # Prints "<gateway> <interface>" of the current LNS route, if any.
      current_route() {
        ip -4 route show "$lns/32" | awk '$2 == "via" && $4 == "dev" { print $3, $5; exit }'
      }

      primary_gateway() {
        ip -4 route show default dev "$primary" | awk '$2 == "via" { print $3; exit }'
      }

      # The LNS pins a session to the address it was set up from, so moving
      # the route means redialling. Hang up first so the goodbye leaves over
      # the old path, while it may still work.
      move_route() {
        local gateway=$1 dev=$2
        if systemctl is-active --quiet xl2tpd.service; then
          systemctl stop xl2tpd.service
          ip -4 route replace "$lns/32" via "$gateway" dev "$dev"
          systemctl start xl2tpd.service
        else
          ip -4 route replace "$lns/32" via "$gateway" dev "$dev"
        fi
      }

      fails=0
      successes=0
      round=0

      on_backup=false
      if [ "$(current_route | awk '{ print $2 }')" = "$backup" ]; then
        on_backup=true
        echo "starting on $backup"
      else
        echo "starting on $primary"
      fi

      while true; do
        if probe; then
          fails=0
          successes=$((successes + 1))
        else
          successes=0
          fails=$((fails + 1))
        fi

        if $on_backup; then
          if [ "$successes" -ge ${toString recoverThreshold} ]; then
            echo "$primary healthy for $successes rounds, moving the tunnel back"
            on_backup=false
          fi
        elif [ "$fails" -ge ${toString failThreshold} ]; then
          echo "$primary unhealthy for $fails rounds, moving the tunnel to $backup"
          on_backup=true
        fi

        if $on_backup; then
          want="$backup_gateway $backup"
        else
          gateway=$(primary_gateway)
          want=''${gateway:+$gateway $primary}
        fi

        if [ -n "$want" ] && [ "$want" != "$(current_route)" ]; then
          echo "routing $lns via $want"
          # shellcheck disable=SC2086
          move_route $want
        fi

        round=$((round + 1))
        sleep ${toString interval}
      done
    '';
  };
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
      enable = lib.mkEnableOption "routing IPv4 over the tunnel. Without it only IPv6 is routed. Requires `underlay` so the LNS is not routed through the tunnel";

      metric = lib.mkOption {
        type = lib.types.int;
        default = 512;
        description = "Metric of the IPv4 default route via the tunnel. Must beat the underlay's own default routes.";
      };
    };

    underlay = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          primaryInterface = lib.mkOption {
            type = lib.types.str;
            description = "Interface the tunnel normally runs over. Its gateway is read from its default route, so it may come from DHCP.";
          };

          backupInterface = lib.mkOption {
            type = lib.types.str;
            description = "Interface the tunnel runs over while the primary is unhealthy.";
          };

          backupGateway = lib.mkOption {
            type = lib.types.str;
            description = "Gateway reached via the backup interface.";
          };

          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
            description = "Public IPs pinged via the primary. The primary is healthy while any of them answers.";
          };
        };
      });
      default = null;
      description = ''
        Underlays the tunnel runs over. When set, a host route to the LNS is
        kept via the primary while it is healthy and via the backup otherwise,
        and the tunnel is redialled whenever that route moves.
      '';
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
        ${defaultRoute}
        +ipv6
        nodefaultroute6
        noccp
        mtu ${toString cfg.mtu}
        mru ${toString cfg.mtu}
        lcp-echo-interval 10
        lcp-echo-failure 6
        ${lib.strings.optionalString (!cfg.ipv4.enable) "ip-up-script ${ipUp}"}
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

    systemd.services.l2tp-underlay = lib.mkIf (cfg.underlay != null) {
      description = "L2TP underlay failover";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = lib.meta.getExe underlayMonitor;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # The LNS host route is installed on a networkd-managed link outside any
    # .network file, which networkd would otherwise remove as foreign.
    systemd.network.config.networkConfig.ManageForeignRoutes =
      lib.mkIf (cfg.underlay != null) false;

    systemd.network.networks."50-${cfg.ifname}" = {
      matchConfig.Name = cfg.ifname;
      networkConfig = {
        DHCP = "ipv6";
        IPv6AcceptRA = false;
        # pppd assigns the addresses, including the link-local one IPV6CP
        # negotiates, which DHCPv6 is sent from. The kernel generates none on
        # ppp links, but networkd only runs DHCPv6 with this enabled.
        LinkLocalAddressing = "ipv6";
        KeepConfiguration = "static";
      };
      dhcpV6Config = {
        WithoutRA = "solicit";
        UseDNS = false;
      } // lib.attrsets.optionalAttrs (cfg.delegatedPrefix != null) {
        PrefixDelegationHint = cfg.delegatedPrefix;
      };
      routes = [
        { Destination = "::/0"; }
      ] ++ lib.lists.optional (cfg.delegatedPrefix != null) {
        # Traffic for unassigned parts of the delegation would otherwise follow
        # the default route straight back up the tunnel.
        Destination = cfg.delegatedPrefix;
        Type = "unreachable";
      };
      # The tunnel only dials once the network is online.
      linkConfig.RequiredForOnline = "no";
    };
  };
}
