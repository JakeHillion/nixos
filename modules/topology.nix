{ config, pkgs, lib, ... }:

{
  options = {
    custom.topology = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Human-readable description of the location";
          };

          routerDevice = lib.mkOption {
            type = lib.types.str;
            description = "Hostname of the router for this location";
          };

          networks = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                description = lib.mkOption {
                  type = lib.types.str;
                  description = "Human-readable description of the network";
                };

                vlanId = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "VLAN ID for this network";
                };

                subnet = lib.mkOption {
                  type = lib.types.str;
                  description = "CIDR notation for the subnet (e.g., 10.0.0.0/24)";
                };

                interface = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Physical interface on the router for this network";
                };

                dhcpEnabled = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether DHCP should be enabled for this network";
                };

                dhcpPool = lib.mkOption {
                  type = lib.types.nullOr (lib.types.submodule {
                    options = {
                      start = lib.mkOption {
                        type = lib.types.str;
                        description = "Start IP address of DHCP pool";
                      };
                      end = lib.mkOption {
                        type = lib.types.str;
                        description = "End IP address of DHCP pool";
                      };
                    };
                  });
                  default = null;
                  description = "DHCP pool configuration";
                };

                devices = lib.mkOption {
                  type = lib.types.attrsOf (lib.types.submodule {
                    options = {
                      hostname = lib.mkOption {
                        type = lib.types.str;
                        description = "Hostname for the device";
                      };

                      fqdn = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Fully qualified domain name for the device";
                      };

                      hwAddress = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "MAC address (required for DHCP reservations, optional for static IPs)";
                      };

                      dhcpReservation = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                        description = "Whether this is a DHCP reservation or just a static IP record";
                      };
                    };
                  });
                  default = { };
                  description = "Reserved IPs in this network. Keys are the host IDs as strings (e.g., \"20\" -> 10.x.x.20)";
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
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Internal IP address to forward to (optional if fqdn is set)";
                      };

                      fqdn = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "FQDN to forward to (looks up IP from reservedIPs if set)";
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
                  description = "Port forwarding rules for this network";
                };
              };
            });
            description = "Networks within this location";
          };

          wanInterface = lib.mkOption {
            type = lib.types.str;
            description = "WAN interface name on the router";
          };

          wanMacAddress = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "MAC address to set on the WAN interface (for ISP identification)";
          };

          staticWanIP = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Static WAN IP address for NAT reflection/loopback (even if the WAN interface uses DHCP)";
          };
        };
      });
      default = { };
      description = "Network topology configuration";
    };
  };

  config = {
    custom.topology = {
      home = {
        description = "Home Network";
        routerDevice = "cyclone.gw.${config.ogygia.domain}";
        wanInterface = "enp2s0";
        wanMacAddress = "b4:fb:e4:b0:90:3c";
        staticWanIP = "185.240.111.53";

        networks = {
          lan = {
            description = "Main LAN Network";
            subnet = "10.64.50.0/24";
            interface = "enp1s0f0";
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.64.50.64";
              end = "10.64.50.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
            ntpServers = [ "10.64.50.1" ];
            internetAccess = true;
            trustedNetwork = true;

            devices = {
              "2" = {
                hostname = "es-16-xg";
                hwAddress = "18:e8:29:26:fe:a9";
                dhcpReservation = true;
              };
              "3" = {
                hostname = "es-48-500w";
                hwAddress = "74:ac:b9:a0:e1:3b";
                dhcpReservation = true;
              };
              "20" = {
                hostname = "rooster";
                fqdn = "rooster.cx.${config.ogygia.domain}";
                hwAddress = "90:e2:ba:d4:84:24";
                dhcpReservation = true;
              };
              "21" = {
                hostname = "warlock";
                fqdn = "warlock.cx.${config.ogygia.domain}";
                hwAddress = "e8:ff:1e:d9:73:5a";
                dhcpReservation = true;
              };
              "22" = {
                hostname = "theon";
                fqdn = "theon.storage.${config.ogygia.domain}";
                hwAddress = "00:1e:06:49:06:1e";
                dhcpReservation = true;
              };
              "24" = {
                hostname = "apc-ap7921";
                hwAddress = "00:c0:b7:6b:f4:34";
                dhcpReservation = true;
              };
              "27" = {
                hostname = "phoenix";
                fqdn = "phoenix.st.${config.ogygia.domain}";
                hwAddress = "f8:f2:1e:1e:b5:74";
                dhcpReservation = true;
              };
              "28" = {
                hostname = "merlin";
                fqdn = "merlin.rig.${config.ogygia.domain}";
                hwAddress = "b0:41:6f:13:20:14";
                dhcpReservation = true;
              };
              "29" = {
                hostname = "stinger";
                fqdn = "stinger.pop.${config.ogygia.domain}";
                hwAddress = "7c:83:34:be:30:dd";
                dhcpReservation = true;
              };
              "30" = {
                hostname = "maverick";
                fqdn = "maverick.cx.${config.ogygia.domain}";
                hwAddress = "38:05:25:34:02:37";
                dhcpReservation = true;
              };
            };
            portForwarding = [
              {
                description = "SSH";
                externalPort = 22;
                internalIP = "10.64.50.1";
                protocol = "tcp";
              }
              {
                description = "WireGuard";
                externalPort = 51820;
                internalIP = "10.64.50.1";
                protocol = "udp";
              }
              {
                description = "HTTP";
                externalPort = 80;
                internalIP = "10.64.50.1";
                protocol = "tcp";
              }
              {
                description = "HTTPS";
                externalPort = 443;
                internalIP = "10.64.50.1";
                protocol = "tcp";
              }
              {
                description = "HTTPS";
                externalPort = 443;
                internalIP = "10.64.50.1";
                protocol = "udp";
              }
              {
                description = "Tang";
                externalPort = 7654;
                internalIP = "10.64.50.1";
                protocol = "tcp";
              }
              {
                description = "DNS (TCP)";
                externalPort = 53;
                internalIP = "10.64.50.1";
                protocol = "tcp";
                loopbackEnabled = false;
              }
              {
                description = "DNS (UDP)";
                externalPort = 53;
                internalIP = "10.64.50.1";
                protocol = "udp";
                loopbackEnabled = false;
              }
              {
                description = "Nebula Lighthouse";
                externalPort = 4242;
                internalIP = "10.64.50.1";
                protocol = "udp";
                loopbackEnabled = true;
              }
            ];
          };

          iot = {
            description = "IoT Devices Network";
            vlanId = 2;
            subnet = "10.239.19.0/24";
            interface = "enp1s0f0"; # Parent interface for VLAN
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.239.19.64";
              end = "10.239.19.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
            ntpServers = [ "10.239.19.1" ];
            internetAccess = true;
            trustedNetwork = true;

            devices = {
              "2" = {
                hostname = "bedroom-everything-presence-one";
                hwAddress = "40:22:d8:e0:1d:50";
                dhcpReservation = true;
              };
              "3" = {
                hostname = "living-room-everything-presence-one";
                hwAddress = "40:22:d8:e0:0f:78";
                dhcpReservation = true;
              };
              "4" = {
                hostname = "hallway-wall-tablet";
                hwAddress = "8c:51:09:20:53:8d";
                dhcpReservation = true;
              };
              "5" = {
                hostname = "fc-ntp-mini";
                hwAddress = null;
                dhcpReservation = false;
              };
              "6" = {
                hostname = "hammer";
                hwAddress = "48:da:35:6f:f2:4b";
                dhcpReservation = true;
              };
              "7" = {
                hostname = "charlie";
                hwAddress = "48:da:35:6f:83:b8";
                dhcpReservation = true;
              };
              "8" = {
                hostname = "stinger";
                hwAddress = "7c:83:34:be:30:dd";
                dhcpReservation = true;
              };
              "9" = {
                hostname = "phoenix-kvm";
                hwAddress = "48:da:35:6f:d5:e5";
                dhcpReservation = true;
              };
              "10" = {
                hostname = "living-room-onju-voice-a1cbf4";
                hwAddress = "30:ed:a0:a1:cb:f4";
                dhcpReservation = true;
              };
              "11" = {
                hostname = "warlock";
                fqdn = "warlock.cx.${config.ogygia.domain}";
                hwAddress = "e8:ff:1e:d9:73:5a";
                dhcpReservation = true;
              };
              "12" = {
                hostname = "argus";
                hwAddress = "48:da:35:6f:0f:a8";
                dhcpReservation = true;
              };
            };
          };

          cameras = {
            description = "Security Cameras Network";
            vlanId = 3;
            subnet = "10.133.145.0/24";
            interface = "enp1s0f0"; # Parent interface for VLAN
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.133.145.64";
              end = "10.133.145.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
            internetAccess = false; # Cameras don't need internet access
            trustedNetwork = false; # Don't allow camera network to access router
          };

          # Note: VLAN 4 = mtu9000, VLAN 5 = cellular (configured on switch, not in topology)

          exo = {
            description = "Exo Devices Network";
            vlanId = 6;
            subnet = "10.185.42.0/24";
            interface = "enp1s0f0";
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.185.42.64";
              end = "10.185.42.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
            internetAccess = true;
            trustedNetwork = false;
          };

          openclaw = {
            description = "OpenClaw Network";
            vlanId = 7;
            subnet = "10.116.242.0/24";
            interface = "enp1s0f0";
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.116.242.64";
              end = "10.116.242.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
            internetAccess = true;
            trustedNetwork = false;

            devices = {
              "2" = {
                hostname = "fanboy";
                fqdn = "fanboy.cx.${config.ogygia.domain}";
                hwAddress = "78:55:36:00:0d:ed";
                dhcpReservation = true;
              };
            };
          };
        };
      };
    };
  };
}
