{ config, lib, ... }:

# The part of the fleet's ogygia configuration that every member shares,
# NixOS host or castaway: the domain and the Nebula mesh. It depends on nothing
# NixOS provides, so castaways evaluate it on their own.

let
  domain = config.ogygia.domain;

  # Flatten the nebula subtree of the authoritative DNS map into the shape
  # `ogygia.nebula.topology.hosts` expects — { "<fqdn>" = { ipv4 = "<ip>"; }; } —
  # so the mesh IP plan stays sourced from modules/dns (single source of
  # truth) rather than being duplicated here.
  nebTree = config.custom.dns.authoritative.ipv4.me.jakehillion.neb;
  nebulaHosts = builtins.listToAttrs (lib.collect (x: x ? name && x ? value)
    (lib.mapAttrsRecursive
      (path: ip: lib.nameValuePair
        "${lib.concatStringsSep "." (lib.reverseList path)}.${domain}"
        { ipv4 = ip; })
      nebTree));

  # Publicly reachable endpoints for the lighthouses, matching the legacy mesh.
  lighthouseEndpoints = {
    "boron.cx.${domain}" = "boron.cx.jakehillion.me:4242";
    "cyclone.gw.${domain}" = "home.jakehillion.me:4242";
    "li.pop.${domain}" = "home.scott.hillion.co.uk:4242";
    "iceman.cx.${domain}" = "iceman.cx.jakehillion.me:4242";
  };
in
{
  imports = [ ../dns/authoritative.nix ];

  ogygia = {
    domain = "neb.jakehillion.me";

    nebula = {
      # Certificates + the (reused) legacy CA cert are content-addressed
      # under the flake-root `nebula/` directory, matching where the
      # `ogygia nebula` CLI reads and writes them.
      certDir = ../../nebula;

      firewall.inbound = [
        # SSH is allowed from every mesh peer, no group required. This keeps
        # admin and inter-host SSH working once legacy-full-access is retired,
        # and (unlike the group rule below) also lets groupless hosts such as
        # fanboy reach the rest of the fleet over Nebula.
        { host = "any"; port = 22; proto = "tcp"; }

        # Reproduce the legacy allow-all inbound posture. Per-host cert groups
        # live in each host's own config (see ogygia.nebula.groups there).
        { groups = [ "legacy-full-access" ]; port = "any"; proto = "any"; }

        # Allow ICMP from any peer, no group, so ping works as a diagnostic.
        { host = "any"; port = "any"; proto = "icmp"; }
      ];

      topology = {
        subnet = "172.20.0.0/24";
        hosts = lib.recursiveUpdate nebulaHosts
          (lib.mapAttrs (_: endpoint: { endpoint = endpoint; }) lighthouseEndpoints);
        lighthouses = builtins.attrNames lighthouseEndpoints;
        relays = [
          "boron.cx.${domain}"
          "cyclone.gw.${domain}"
        ];
      };
    };
  };
}
