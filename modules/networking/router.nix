{ config, pkgs, lib, ... }:

let
  cfg = config.custom.networking.router;
  registry = config.custom.network;

  ip = import ./lib.nix { inherit lib; };
in
{
  options.custom.networking.router = {
    auto = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to route the networks the registry assigns to this host";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Interface carrying the networks' VLANs";
    };

    networks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          subnetId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "ID of this network's DHCP subnet. Leases are stored under it, so it must never change.";
          };

          dnsServers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "DNS servers for this network";
          };

          ntpServers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "NTP servers for this network";
          };

          internetAccess = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this network has access to the internet";
          };

          trustedNetwork = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this network is trusted to access the router";
          };
        };
      });
      description = "Router settings for the networks this host routes, by network name";
    };

    portForwarding = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Description of the port forwarding rule";
          };

          externalPort = lib.mkOption {
            type = lib.types.int;
            description = "External port to forward";
          };

          internalIP = lib.mkOption {
            type = lib.types.str;
            description = "Internal IP address to forward to";
          };

          internalPort = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Internal port to forward to (defaults to same as external)";
          };

          protocol = lib.mkOption {
            type = lib.types.enum [ "tcp" "udp" "both" ];
            default = "tcp";
            description = "Protocol for port forwarding";
          };

          loopbackEnabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable NAT loopback for this port forward";
          };
        };
      });
      default = [ ];
      description = "Port forwarding rules";
    };

    wanInterface = lib.mkOption {
      type = lib.types.str;
      description = "WAN interface name on the router";
    };

    uplinkInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Physical interface the WAN is carried over, when the WAN interface
        is a tunnel. It takes DHCP and the WAN MAC address, and inbound
        traffic on it is dropped like the WAN's.
      '';
    };

    wanMacAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "MAC address to set on the WAN interface, or on the uplink interface if set (for ISP identification)";
    };

    staticWanIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static WAN IP address for NAT reflection/loopback (even if the WAN interface uses DHCP)";
    };

    routedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Public IPv4 subnets the ISP routes to the WAN address. Traffic sourced from them leaves the WAN without masquerading.";
    };

    extraForwardRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules to add to the forward chain";
    };

    extraInputRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules to add to the input chain";
    };

    extraNatRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules to add to the NAT postrouting chain";
    };
  };

  config =
    let
      # The registry names fleet hosts by their FQDN without the fleet domain
      self = lib.strings.removeSuffix ".${config.ogygia.domain}" config.networking.fqdn;

      # Networks this host routes, with their router settings
      routed = lib.attrsets.filterAttrs (_: netCfg: netCfg.router == self) registry.networks;
      networks = lib.attrsets.mapAttrs (netName: netCfg: netCfg // cfg.networks.${netName}) routed;

      # Filter networks that have DHCP enabled
      dhcpNetworks = lib.attrsets.filterAttrs (_: netCfg: netCfg.pool != null) networks;

      # Physical interface that takes DHCP and the WAN MAC
      uplinkInterface =
        if cfg.uplinkInterface != null then cfg.uplinkInterface else cfg.wanInterface;

      # Interfaces whose inbound traffic is dropped unless explicitly allowed
      untrustedInterfaces = lib.lists.unique [ cfg.wanInterface uplinkInterface ];

      # Each network's interface on the router is a VLAN named after it
      trustedInterfaceNames = lib.attrsets.attrNames
        (lib.attrsets.filterAttrs (_: netCfg: netCfg.trustedNetwork) networks);
      internetInterfaceNames = lib.attrsets.attrNames
        (lib.attrsets.filterAttrs (_: netCfg: netCfg.internetAccess) networks);

      # Helper for protocol-specific rules
      protocolRules = protocol:
        if protocol == "both" then [ "tcp" "udp" ] else [ protocol ];

      # Helper to determine if a port forward is for the router itself
      isRouterService = rule:
        builtins.elem rule.internalIP (lib.attrsets.mapAttrsToList (_: netCfg: netCfg.gateway) networks);

      # DHCP reservations for the registered devices with an address on a network
      reservations = netName:
        let
          devices = lib.attrsets.filterAttrs
            (_: device: device.mac != null && (device.net.${netName}.ipv4 or null) != null)
            registry.devices;
          address = devName: devices.${devName}.net.${netName}.ipv4;
        in
        map
          (devName: {
            ip-address = address devName;
            hw-address = devices.${devName}.mac;
            hostname = lib.lists.head (lib.strings.splitString "." devName);
          })
          (lib.lists.sort (a: b: ip.toInt (address a) < ip.toInt (address b)) (lib.attrsets.attrNames devices));
    in
    lib.mkIf cfg.auto {
      # Every routed network has router settings, even if only the defaults
      custom.networking.router.networks = lib.attrsets.mapAttrs (_: _: { }) routed;

      networking = {
        # Disable firewall and NAT since we'll configure nftables
        firewall.enable = lib.mkForce false;
        nat.enable = lib.mkForce false;

        # Disable global DHCP - we'll configure per interface
        useDHCP = false;

        # Each network is a VLAN on the trunk interface
        vlans = lib.attrsets.mapAttrs
          (_: netCfg: {
            id = netCfg.vlan;
            interface = cfg.interface;
          })
          networks;

        # Configure network interfaces
        interfaces =
          # WAN interface
          {
            "${uplinkInterface}" = {
              useDHCP = true;
              macAddress = cfg.wanMacAddress;
            };
          } //
          # The router is the gateway of each network
          lib.attrsets.mapAttrs
            (_: netCfg: {
              ipv4.addresses = [
                {
                  address = netCfg.gateway;
                  prefixLength = ip.prefixLength netCfg.ipv4;
                }
              ];
            })
            networks;

        # Configure nftables firewall
        nftables = {
          enable = true;
          ruleset = ''
            table inet filter {
              chain output {
                type filter hook output priority 100; policy accept;
              }

              chain input {
                type filter hook input priority filter; policy drop;

                # Allow all loopback traffic
                iifname "lo" counter accept

                # Allow trusted networks to access the router
                iifname {
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") (["lo"] ++ trustedInterfaceNames ++ ["neb.ogygia"]))}
                } counter accept

                # Allow ICMP from anywhere
                ip protocol icmp counter accept comment "accept all ICMP types"

                # Allow established connections
                ct state { established, related } counter accept

                # Allow specific services from WAN (both router services and port forwarding)
                ${lib.strings.concatStringsSep "\n    " 
                  (lib.lists.flatten 
                    (map (rule: 
                      map (proto: 
                        "meta nfproto ipv4 iifname \"${cfg.wanInterface}\" ${proto} dport ${toString rule.externalPort} counter accept comment \"${rule.description}\""
                      ) (protocolRules rule.protocol)
                    ) cfg.portForwarding)
                  )
                }

                # Extra input rules
                ${cfg.extraInputRules}

                # Drop all other WAN traffic
                iifname {
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") untrustedInterfaces)}
                } counter drop
              }

              chain forward {
                type filter hook forward priority filter; policy drop;

                # Allow trusted LAN to WAN (internet access)
                meta nfproto ipv4 iifname {
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") internetInterfaceNames)}
                } oifname {
                  "${cfg.wanInterface}"
                } counter accept comment "Allow trusted LAN to WAN"

                # Allow established connections back to LANs
                meta nfproto ipv4 iifname {
                  "${cfg.wanInterface}"
                } oifname {
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") internetInterfaceNames)}
                } ct state { established, related } counter accept comment "Allow established back to LANs"

                # Port forwarding rules from all networks
                ${lib.strings.concatStringsSep "\n    " 
                  (map (rule: 
                    if rule.internalPort != null then
                      "ip daddr ${rule.internalIP} ${rule.protocol} dport ${toString rule.internalPort} counter accept comment \"${rule.description}\""
                    else
                      "ip daddr ${rule.internalIP} ${rule.protocol} dport ${toString rule.externalPort} counter accept comment \"${rule.description}\""
                  ) cfg.portForwarding)
                }

                # Extra forward rules
                ${cfg.extraForwardRules}
              }
            }

            table ip nat {
              chain prerouting {
                type nat hook prerouting priority filter; policy accept;

                # Port forwarding (skip DNAT for router services)
                ${lib.strings.concatStringsSep "\n    " 
                  (map (rule: 
                    "iifname ${cfg.wanInterface} ${rule.protocol} dport ${toString rule.externalPort} counter dnat to ${rule.internalIP}:${
                      toString (if rule.internalPort != null then rule.internalPort else rule.externalPort)
                    }"
                  ) (lib.lists.filter (rule: !(isRouterService rule)) cfg.portForwarding))
                }
                
                # NAT loopback/reflection for internal clients accessing WAN IP
                ${lib.strings.optionalString (cfg.staticWanIP != null) (
                  lib.strings.concatStringsSep "\n    " 
                  (lib.lists.flatten 
                    (map (rule: 
                      if (rule.loopbackEnabled) then
                        # Clients connect from the trusted networks
                        map (iface:
                          "iifname ${iface} ip daddr ${cfg.staticWanIP} ${rule.protocol} dport ${toString rule.externalPort} counter dnat to ${rule.internalIP}:${
                            toString (if rule.internalPort != null then rule.internalPort else rule.externalPort)
                          }"
                        ) trustedInterfaceNames
                      else
                        []
                    ) cfg.portForwarding)
                  )
                )}
              }

              chain postrouting {
                type nat hook postrouting priority filter; policy accept;

                # Masquerade outgoing WAN traffic
                oifname "${cfg.wanInterface}" ${lib.strings.optionalString (cfg.routedSubnets != [ ]) "ip saddr != { ${lib.strings.concatStringsSep ", " cfg.routedSubnets} } "}masquerade

                # Extra NAT rules
                ${cfg.extraNatRules}
              }
            }
          '';
        };
      };

      # Configure kernel IP forwarding for routing
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = true;
      };
      # Set the WAN MAC via a .link file so udev applies it the moment the
      # interface appears (in initrd too, since stage 2 .link files are bundled
      # into systemd stage 1's initramfs). Needed for tang/clevis unlock against
      # an upstream that expects a stable MAC.
      systemd.network.links."10-${uplinkInterface}" = lib.mkIf (config.custom.tang.enable && cfg.wanMacAddress != null) {
        matchConfig.OriginalName = uplinkInterface;
        linkConfig.MACAddress = cfg.wanMacAddress;
      };

      # The router resolves through its configured nameservers. Ignoring the
      # lease's DNS servers also stops networkd pinning host routes to them via
      # the uplink.
      systemd.network.networks = lib.mkIf config.networking.useNetworkd ({
        "40-${uplinkInterface}".dhcpV4Config.UseDNS = false;
      } //
      # The VLANs' parent carries no addresses and never leaves the configuring
      # state, which holds network-online.target until wait-online times out.
      {
        "40-${cfg.interface}".linkConfig.RequiredForOnline = "no";
      });

      custom.impermanence.extraDirs = lib.mkIf (config.custom.impermanence.enable && dhcpNetworks != { }) [
        "/var/lib/private/kea"
      ];

      # Configure DHCP server for networks that have it enabled
      services.kea.dhcp4 = lib.mkIf (dhcpNetworks != { }) {
        enable = true;

        settings = {
          # Configure interfaces for DHCP
          interfaces-config = {
            interfaces = lib.attrsets.attrNames dhcpNetworks;
          };

          lease-database = {
            type = "memfile";
            persist = true;
            name = "/var/lib/kea/dhcp4.leases";
          };

          # Define APC option for vendor-specific requirements
          option-def = [
            {
              name = "cookie";
              space = "vendor-encapsulated-options-space";
              code = 1;
              type = "string";
              array = false;
            }
          ];

          # Define APC client class
          client-classes = [
            {
              name = "APC";
              test = "option[vendor-class-identifier].text == 'APC'";
              option-data = [
                {
                  always-send = true;
                  name = "vendor-encapsulated-options";
                }
                {
                  name = "cookie";
                  space = "vendor-encapsulated-options-space";
                  code = 1;
                  data = "1APC";
                }
              ];
            }
          ];

          # Configure DHCP subnets
          subnet4 =
            lib.attrsets.mapAttrsToList
              (name: netCfg: {
                id = netCfg.subnetId;
                subnet = netCfg.ipv4;
                interface = name;

                # Configure DHCP pools
                pools = [{
                  pool = "${netCfg.pool.start} - ${netCfg.pool.end}";
                }];

                # Configure DHCP options
                option-data = [
                  {
                    name = "routers";
                    data = netCfg.gateway;
                  }
                  {
                    name = "broadcast-address";
                    data = ip.broadcast netCfg.ipv4;
                  }
                  {
                    name = "domain-name-servers";
                    data = lib.strings.concatStringsSep ", "
                      (if netCfg.dnsServers != [ ] then netCfg.dnsServers else [ "1.1.1.1" "8.8.8.8" ]);
                  }
                ] ++ (lib.lists.optional (netCfg.ntpServers != [ ]) {
                  name = "ntp-servers";
                  data = lib.strings.concatStringsSep ", " netCfg.ntpServers;
                });

                reservations = reservations name;
              })
              dhcpNetworks;
        };
      };

      systemd.services.kea-dhcp4-server = lib.mkIf (dhcpNetworks != { }) {
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "15s";
        };
      };
    };
}
