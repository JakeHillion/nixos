{ config, pkgs, lib, ... }:

let
  cfg = config.custom.router;
  topology = config.custom.topology;
in
{
  options.custom.router = {
    auto = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to automatically configure network interfaces based on topology";
    };

    extraForwardRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules to add to the forward chain";
    };

    extraNatRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules to add to the NAT postrouting chain";
    };
  };

  config =
    let
      locationCfg = lib.lists.findSingle (loc: loc.routerDevice == config.networking.fqdn) null "multiple" (lib.attrsets.attrValues topology);

      # Helper functions to work with CIDR notation
      getCidrPrefixLength = cidr:
        let
          parts = lib.strings.splitString "/" cidr;
        in
        lib.strings.toInt (lib.lists.elemAt parts 1);

      # Calculate the gateway IP (always .1 in the subnet)
      calculateGateway = cidr:
        let
          parts = lib.strings.splitString "/" cidr;
          subnetParts = lib.strings.splitString "." (lib.lists.elemAt parts 0);
          # Replace the last octet with 1
          gatewayParts = (lib.lists.take 3 subnetParts) ++ [ "1" ];
        in
        lib.strings.concatStringsSep "." gatewayParts;

      # Get the gateway address (always .1 in the subnet)
      getGateway = netCfg: calculateGateway netCfg.subnet;

      # Simplify: Just return the broadcast address based on the subnet format
      # For a /24 subnet, replace the last octet with 255
      calculateBroadcast = cidr:
        let
          parts = lib.strings.splitString "/" cidr;
          ip = lib.lists.elemAt parts 0;
          prefix = lib.strings.toInt (lib.lists.elemAt parts 1);
          ipParts = lib.strings.splitString "." ip;

          # Handle different prefix lengths
          result =
            if prefix == 24 then
            # For /24, set last octet to 255
              "${lib.lists.elemAt ipParts 0}.${lib.lists.elemAt ipParts 1}.${lib.lists.elemAt ipParts 2}.255"
            else if prefix == 16 then
            # For /16, set last two octets to 255
              "${lib.lists.elemAt ipParts 0}.${lib.lists.elemAt ipParts 1}.255.255"
            else if prefix == 8 then
            # For /8, set last three octets to 255
              "${lib.lists.elemAt ipParts 0}.255.255.255"
            else
            # Default fallback for other prefix lengths
            # This is a simplification - for other subnet sizes, we would need a more complex calculation
              "${lib.lists.elemAt ipParts 0}.${lib.lists.elemAt ipParts 1}.${lib.lists.elemAt ipParts 2}.255";
        in
        result;

      # Calculate broadcast for a network
      getBroadcast = netCfg: calculateBroadcast netCfg.subnet;

      # Filter networks that have VLANs
      vlanNetworks = lib.attrsets.filterAttrs (name: netCfg: netCfg.vlanId != null) locationCfg.networks;

      # Filter networks that have DHCP enabled
      dhcpNetworks = lib.attrsets.filterAttrs (name: netCfg: netCfg.dhcpEnabled) locationCfg.networks;

      # Get interface name for a network (handles regular interfaces and VLANs)
      getInterfaceName = name: netCfg:
        if netCfg.vlanId == null then netCfg.interface else name;

      # Filter trusted networks (for router access)
      trustedNetworks = lib.attrsets.filterAttrs (name: netCfg: netCfg.trustedNetwork) locationCfg.networks;

      # Filter networks with internet access
      internetNetworks = lib.attrsets.filterAttrs (name: netCfg: netCfg.internetAccess) locationCfg.networks;

      # Get a list of trusted interface names
      trustedInterfaceNames = lib.attrsets.mapAttrsToList getInterfaceName trustedNetworks;

      # Get a list of internet-enabled interface names
      internetInterfaceNames = lib.attrsets.mapAttrsToList getInterfaceName internetNetworks;

      # Helper for protocol-specific rules
      protocolRules = protocol:
        if protocol == "both" then [ "tcp" "udp" ] else [ protocol ];

      # Helper to find IP address for an FQDN from devices
      findIpByFqdn = fqdn:
        let
          # For each network, search through devices for matching FQDN
          matches = lib.lists.flatten (lib.attrsets.mapAttrsToList
            (netName: netCfg:
              let
                prefix = lib.strings.concatStringsSep "." (lib.lists.take 3 (lib.strings.splitString "." (lib.lists.elemAt (lib.strings.splitString "/" netCfg.subnet) 0)));
                hostMatches = lib.attrsets.mapAttrsToList
                  (hostId: hostCfg:
                    if hostCfg.fqdn == fqdn then
                      "${prefix}.${hostId}"
                    else
                      null
                  )
                  (netCfg.devices or { });
              in
              lib.lists.filter (ip: ip != null) hostMatches
            )
            locationCfg.networks);
        in
        if matches == [ ] then null else lib.lists.head matches;

      # Helper to determine if a port forward is for the router itself
      isRouterService = rule:
        let
          # Get effective internal IP (resolve from FQDN if needed)
          effectiveIP =
            if rule.internalIP != null then rule.internalIP
            else if rule.fqdn != null then findIpByFqdn rule.fqdn
            else null;
          # Get all gateway IPs
          gatewayIPs = lib.attrsets.mapAttrsToList (name: netCfg: getGateway netCfg) locationCfg.networks;
        in
        effectiveIP != null && builtins.elem effectiveIP gatewayIPs;

      # Helper to resolve all port forwarding rules across all networks
      getAllPortForwardingRules =
        lib.lists.flatten (
          lib.attrsets.mapAttrsToList
            (netName: netCfg:
              # For each rule in this network
              map
                (rule:
                  let
                    # Resolve internal IP if it's not explicitly set
                    effectiveIP =
                      if rule.internalIP != null then rule.internalIP
                      else if rule.fqdn != null then
                        let
                          # Calculate IP from the current network and host ID
                          matches = lib.attrsets.mapAttrsToList
                            (hostId: hostCfg:
                              if hostCfg.fqdn == rule.fqdn then
                                let
                                  prefix = lib.strings.concatStringsSep "." (lib.lists.take 3 (lib.strings.splitString "." (lib.lists.elemAt (lib.strings.splitString "/" netCfg.subnet) 0)));
                                in
                                "${prefix}.${hostId}"
                              else
                                null
                            )
                            (netCfg.devices or { });
                          resolvedMatches = lib.lists.filter (ip: ip != null) matches;
                        in
                        if resolvedMatches == [ ] then null else lib.lists.head resolvedMatches
                      else null;
                  in
                  # Only include rules that have a resolved IP
                  if effectiveIP != null then
                    {
                      inherit (rule) description externalPort protocol loopbackEnabled;
                      internalIP = effectiveIP;
                      internalPort = rule.internalPort;
                    }
                  else
                    null
                )
                (netCfg.portForwarding or [ ])
            )
            locationCfg.networks
        );

    in
    lib.mkIf (cfg.auto && locationCfg != null) {
      networking = {
        # Disable firewall and NAT since we'll configure nftables
        firewall.enable = lib.mkForce false;
        nat.enable = lib.mkForce false;

        # Disable global DHCP - we'll configure per interface
        useDHCP = false;

        # Configure VLANs for networks that need them
        vlans = lib.attrsets.mapAttrs
          (name: netCfg: {
            id = netCfg.vlanId;
            interface = netCfg.interface;
          })
          vlanNetworks;

        # Configure network interfaces
        interfaces =
          # WAN interface
          {
            "${locationCfg.wanInterface}" = {
              useDHCP = true;
              macAddress = locationCfg.wanMacAddress;
            };
          } //
          # Regular interfaces and VLANs
          lib.attrsets.mapAttrs'
            (name: netCfg:
              lib.attrsets.nameValuePair
                (if netCfg.vlanId == null then netCfg.interface else name)
                {
                  ipv4.addresses = [
                    {
                      address = getGateway netCfg;
                      prefixLength = getCidrPrefixLength netCfg.subnet;
                    }
                  ];
                }
            )
            locationCfg.networks;

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
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") (["lo"] ++ trustedInterfaceNames ++ ["neb.jh"]))}
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
                        "iifname \"${locationCfg.wanInterface}\" ${proto} dport ${toString rule.externalPort} counter accept comment \"${rule.description}\""
                      ) (protocolRules rule.protocol)
                    ) (lib.lists.filter (rule: rule != null) getAllPortForwardingRules))
                  )
                }

                # Drop all other WAN traffic
                iifname { "${locationCfg.wanInterface}" } counter drop
              }

              chain forward {
                type filter hook forward priority filter; policy drop;

                # Allow trusted LAN to WAN (internet access)
                iifname {
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") internetInterfaceNames)}
                } oifname {
                  "${locationCfg.wanInterface}"
                } counter accept comment "Allow trusted LAN to WAN"

                # Allow established connections back to LANs
                iifname {
                  "${locationCfg.wanInterface}"
                } oifname {
                  ${lib.strings.concatStringsSep ",\n      " (map (i: "\"${i}\"") trustedInterfaceNames)}
                } ct state { established, related } counter accept comment "Allow established back to LANs"

                # Port forwarding rules from all networks
                ${lib.strings.concatStringsSep "\n    " 
                  (map (rule: 
                    if rule.internalPort != null then
                      "ip daddr ${rule.internalIP} ${rule.protocol} dport ${toString rule.internalPort} counter accept comment \"${rule.description}\""
                    else
                      "ip daddr ${rule.internalIP} ${rule.protocol} dport ${toString rule.externalPort} counter accept comment \"${rule.description}\""
                  ) (lib.lists.filter (rule: rule != null) getAllPortForwardingRules))
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
                    "iifname ${locationCfg.wanInterface} ${rule.protocol} dport ${toString rule.externalPort} counter dnat to ${rule.internalIP}:${
                      toString (if rule.internalPort != null then rule.internalPort else rule.externalPort)
                    }"
                  ) (lib.lists.filter (rule: rule != null && !(isRouterService rule)) getAllPortForwardingRules))
                }
                
                # NAT loopback/reflection for internal clients accessing WAN IP
                ${lib.strings.optionalString (locationCfg.staticWanIP != null) (
                  lib.strings.concatStringsSep "\n    " 
                  (lib.lists.flatten 
                    (map (rule: 
                      if (rule.loopbackEnabled) then
                        let
                          # Find the LAN interface where clients will connect from
                          lanInterfaces = lib.attrsets.mapAttrsToList
                            (name: netCfg: 
                              if netCfg.trustedNetwork then getInterfaceName name netCfg else null
                            )
                            (lib.attrsets.filterAttrs (name: netCfg: netCfg.trustedNetwork) locationCfg.networks);
                          filteredInterfaces = lib.lists.filter (i: i != null) lanInterfaces;
                        in
                        map (iface: 
                          "iifname ${iface} ip daddr ${locationCfg.staticWanIP} ${rule.protocol} dport ${toString rule.externalPort} counter dnat to ${rule.internalIP}:${
                            toString (if rule.internalPort != null then rule.internalPort else rule.externalPort)
                          }"
                        ) filteredInterfaces
                      else
                        []
                    ) (lib.lists.filter (rule: rule != null) getAllPortForwardingRules))
                  )
                )}
              }

              chain postrouting {
                type nat hook postrouting priority filter; policy accept;

                # Masquerade outgoing WAN traffic
                oifname "${locationCfg.wanInterface}" masquerade

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
      boot.initrd.postDeviceCommands = lib.mkIf (config.custom.tang.enable && locationCfg.wanMacAddress != null) ''
        ip link set dev ${locationCfg.wanInterface} address ${locationCfg.wanMacAddress}
      '';

      # Configure DHCP server for networks that have it enabled
      services.kea.dhcp4 = lib.mkIf (dhcpNetworks != { }) {
        enable = true;

        settings = {
          # Configure interfaces for DHCP
          interfaces-config = {
            interfaces = lib.attrsets.mapAttrsToList getInterfaceName dhcpNetworks;
          };

          # Use persistent memfile database for leases
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
            let
              # Create a list of names with their index
              networksWithIndex = lib.lists.imap0
                (idx: name: { inherit idx name; })
                (lib.attrsets.attrNames locationCfg.networks);

              # Convert to an attrset for easy lookup
              indexByName = lib.attrsets.listToAttrs
                (map (x: lib.attrsets.nameValuePair x.name x.idx) networksWithIndex);
            in
            lib.attrsets.mapAttrsToList
              (name: netCfg: {
                # Use the index of the network in the list + 1 as the subnet ID
                id = 1 + (indexByName.${name} or 0);
                subnet = netCfg.subnet;
                interface = getInterfaceName name netCfg;

                # Configure DHCP pools
                pools = [{
                  pool = "${netCfg.dhcpPool.start} - ${netCfg.dhcpPool.end}";
                }];

                # Configure DHCP options
                option-data = [
                  {
                    name = "routers";
                    data = getGateway netCfg;
                  }
                  {
                    name = "broadcast-address";
                    data = getBroadcast netCfg;
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

                # Configure DHCP reservations from devices
                reservations = lib.attrsets.mapAttrsToList
                  (id: reservation:
                    let
                      # Get the first 3 octets from the subnet
                      subnetBase = lib.strings.splitString "/" netCfg.subnet;
                      subnetParts = lib.strings.splitString "." (lib.lists.elemAt subnetBase 0);
                      subnetPrefix = lib.strings.concatStringsSep "." (lib.lists.take 3 subnetParts);
                      # Create IP address by combining subnet prefix with ID
                      idNum = if builtins.isString id then lib.strings.toInt id else id;
                      ipAddress = "${subnetPrefix}.${toString idNum}";
                    in
                    {
                      ip-address = ipAddress;
                      hw-address = reservation.hwAddress;
                      hostname = reservation.hostname;
                    }
                  )
                  (lib.attrsets.filterAttrs
                    (id: reservation: reservation.dhcpReservation && reservation.hwAddress != null)
                    (netCfg.devices or { }));
              })
              dhcpNetworks;
        };
      };
    };
}
