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

                dnsServers = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "DNS servers for this network";
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
        routerDevice = "cyclone.gw.neb.jakehillion.me";
        wanInterface = "enp2s0";
        wanMacAddress = "b4:fb:e4:b0:90:3d"; # Temporary unique MAC address for testing

        networks = {
          lan = {
            description = "Main LAN Network";
            subnet = "10.91.135.0/24";
            interface = "enp1s0f0";
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.91.135.64";
              end = "10.91.135.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
          };

          iot = {
            description = "IoT Devices Network";
            vlanId = 102;
            subnet = "10.37.106.0/24";
            interface = "enp1s0f0"; # Parent interface for VLAN
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.37.106.64";
              end = "10.37.106.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
          };

          cameras = {
            description = "Security Cameras Network";
            vlanId = 103;
            subnet = "10.139.43.0/24";
            interface = "enp1s0f0"; # Parent interface for VLAN
            dhcpEnabled = true;
            dhcpPool = {
              start = "10.139.43.64";
              end = "10.139.43.254";
            };
            dnsServers = [ "1.1.1.1" "8.8.8.8" ];
          };
        };
      };
    };
  };
}
