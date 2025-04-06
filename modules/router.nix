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
      };

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
                ];
              })
              dhcpNetworks;
        };
      };
    };
}
