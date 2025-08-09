{ config, lib, ... }:

let
  cfg = config.custom.services.zookeeper;
in
{
  options.custom.services.zookeeper = {
    enable = lib.mkEnableOption "zookeeper";

    servers = lib.mkOption {
      readOnly = true;
      type = with lib.types; attrsOf (nullOr str);
      description = "Map from ZooKeeper server ID to hostname. Use null for removed servers.";

      default = {
        "1" = "boron.cx.neb.jakehillion.me";
        "2" = "warlock.cx.neb.jakehillion.me";
        "3" = "li.pop.neb.jakehillion.me";
      };
    };

    clientHosts = lib.mkOption {
      readOnly = true;
      type = with lib.types; listOf str;
      description = "List of ZooKeeper client connection strings (Nebula IPs)";
    };

    clientConnectionString = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
      description = "ZooKeeper client connection string for applications";
    };
  };

  config = lib.mkMerge [
    # Always provide client connection information, even if ZooKeeper is not enabled on this host
    {
      custom.services.zookeeper =
        let
          # Get active servers from the ID mapping (filter out nulls)
          activeServers = lib.filterAttrs (id: hostname: hostname != null) cfg.servers;

          # Function to lookup FQDN in DNS config
          lookupFqdn = fqdn: lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." fqdn)) null config.custom.dns.authoritative.ipv4;

          # Get Nebula IPs for all active servers
          clientHosts = lib.mapAttrsToList (id: hostname: "${lookupFqdn hostname}:2181") activeServers;
        in
        {
          inherit clientHosts;
          clientConnectionString = lib.concatStringsSep "," clientHosts;
        };
    }

    (lib.mkIf cfg.enable (
      let
        # Get active servers from the ID mapping (filter out nulls)
        activeServers = lib.filterAttrs (id: hostname: hostname != null) cfg.servers;

        # Function to lookup FQDN in DNS config
        lookupFqdn = fqdn: lib.attrsets.attrByPath (lib.reverseList (lib.splitString "." fqdn)) null config.custom.dns.authoritative.ipv4;

        # Find the current server ID by looking up hostname
        currentId = lib.lists.findFirst
          (id: cfg.servers.${id} == config.networking.fqdn)
          (throw "Host ${config.networking.fqdn} not found in zookeeper servers")
          (lib.attrNames cfg.servers);

        # Generate server list for ZooKeeper configuration using Nebula IPs
        servers = lib.concatStringsSep "\n" (
          lib.mapAttrsToList
            (id: hostname:
              let nebulaIp = lookupFqdn hostname;
              in "server.${id}=${nebulaIp}:2888:3888")
            activeServers
        );
      in
      {
        services.zookeeper = {
          enable = true;
          id = lib.toInt currentId;
          dataDir = lib.mkIf config.custom.impermanence.enable
            "${config.custom.impermanence.base}/system/var/lib/zookeeper";

          inherit servers;

          extraConf = ''
            admin.serverPort=0
            clientPortAddress=${config.custom.dns.nebula.ipv4}

            tickTime=2000
            initLimit=10
            syncLimit=5
          '';
        };
      }
    ))
  ];
}
