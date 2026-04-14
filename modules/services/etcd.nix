{ config, lib, ... }:

let
  cfg = config.custom.services.etcd;
  locations = config.custom.locations.locations;
in
{
  options.custom.services.etcd = {
    enable = lib.mkEnableOption "etcd";

    endpoints = lib.mkOption {
      readOnly = true;
      type = with lib.types; listOf str;
      description = "List of etcd client endpoints (Nebula IPs with port 2379)";
    };
  };

  config = lib.mkMerge [
    # Always provide endpoint information, even if etcd is not enabled on this host
    {
      custom.services.etcd =
        let
          # Get the list of etcd hosts from locations.nix
          etcdHosts = locations.services.etcd;

          # Function to lookup FQDN in DNS config (same pattern as zookeeper.nix)
          lookupFqdn = fqdn:
            lib.attrsets.attrByPath
              (lib.reverseList (lib.splitString "." fqdn))
              null
              config.custom.dns.authoritative.ipv4;

          # Generate client endpoints for all etcd hosts
          endpoints = map
            (hostname:
              let nebulaIp = lookupFqdn hostname;
              in "http://${nebulaIp}:2379")
            etcdHosts;
        in
        {
          inherit endpoints;
        };
    }

    (lib.mkIf cfg.enable (
      let
        # Get the list of etcd hosts from locations.nix
        etcdHosts = locations.services.etcd;

        # Function to lookup FQDN in DNS config (same pattern as zookeeper.nix)
        lookupFqdn = fqdn:
          lib.attrsets.attrByPath
            (lib.reverseList (lib.splitString "." fqdn))
            null
            config.custom.dns.authoritative.ipv4;

        # Get this host's nebula IP
        thisNebulaIp = config.custom.dns.nebula.ipv4;

        # Generate initial cluster list
        initialCluster = map
          (hostname:
            let nebulaIp = lookupFqdn hostname;
            in "${hostname}=http://${nebulaIp}:2380")
          etcdHosts;

        # Check if this host is in the cluster
        isClusterMember = builtins.elem config.networking.fqdn etcdHosts;
      in
      lib.mkIf isClusterMember {
        users.users.etcd.uid = config.ids.uids.etcd;
        users.groups.etcd.gid = config.ids.gids.etcd;

        services.etcd = {
          enable = true;

          name = config.networking.fqdn;
          listenClientUrls = [ "http://${thisNebulaIp}:2379" ];
          listenPeerUrls = [ "http://${thisNebulaIp}:2380" ];
          initialCluster = initialCluster;
          initialAdvertisePeerUrls = [ "http://${thisNebulaIp}:2380" ];

          dataDir = lib.mkIf config.custom.impermanence.enable
            "${config.custom.impermanence.base}/system/var/lib/etcd";
        };

        # Add data directory to impermanence if not using the services.etcd.dataDir override
        custom.impermanence.extraDirs = lib.mkIf (!config.custom.impermanence.enable) [ ];
      }
    ))
  ];
}
