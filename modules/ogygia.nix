{ pkgs, lib, config, ... }:

let
  cfg = config.custom.ogygia;

  allHosts = builtins.attrNames (builtins.readDir ../hosts);
  hosts = builtins.filter (h: h != "fanboy.cx.neb.jakehillion.me" && h != config.networking.fqdn) allHosts;

  domain = config.ogygia.domain;
  user = config.custom.user;

  # Flatten the nebula subtree of the authoritative DNS map into the shape
  # `ogygia.nebula.topology.hosts` expects — { "<fqdn>" = { ipv4 = "<ip>"; }; } —
  # so the mesh IP plan stays sourced from modules/dns.nix (single source of
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
  };

  # Operator CA private key location for `ogygia nebula rekey`. Lives in the
  # synced `sync` folder (via the /home/<user>/local impermanence symlink).
  caKeyTarget = "${config.users.users.${user}.home}/local/sync/sync/keys/nebula-ca-2527.key";
in
{
  options.custom.ogygia = {
    enable = lib.mkEnableOption "ogygia";
  };

  config = lib.mkIf cfg.enable {
    ogygia = {
      enable = true;
      domain = "neb.jakehillion.me";

      gitRemoteUrl = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";

      irisd = {
        enable = true;
        configureNixDaemon = true;

        settings.peers.urls = builtins.map (fqdn: "http://${fqdn}:35742") hosts;
      };

      etcd = {
        endpoints = config.custom.services.etcd.endpoints;
      };

      # Fleet-wide configuration for the ogygia-managed Nebula overlay, which
      # replaces the legacy custom.nebula mesh. Enabled by default; hosts whose
      # keypair hasn't been grabbed yet opt out in their own config.
      nebula = {
        enable = true;

        # Certificates + the (reused) legacy CA cert are content-addressed
        # under the flake-root `nebula/` directory, matching where the
        # `ogygia nebula` CLI reads and writes them.
        certDir = ../nebula;

        firewall.inbound = [
          # SSH is allowed from every mesh peer, no group required. This keeps
          # admin and inter-host SSH working once legacy-full-access is retired,
          # and (unlike the group rule below) also lets groupless hosts such as
          # fanboy reach the rest of the fleet over Nebula.
          { host = "any"; port = 22; proto = "tcp"; }

          # Reproduce the legacy allow-all inbound posture. Per-host cert groups
          # live in each host's own config (see ogygia.nebula.groups there).
          { groups = [ "legacy-full-access" ]; port = "any"; proto = "any"; }
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

    environment.systemPackages = [ pkgs.ogygia ];

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/cache/private/ogygia-irisd" ];

    # Reuse the legacy Nebula keypair. The private key stays at its existing
    # /data/nebula/host.key (persistent, already owned by the nebula service
    # uid) — point the network straight at it rather than via /etc/nebula,
    # which the module locks to 0700 root and the service user can't traverse.
    services.nebula.networks.ogygia = lib.mkIf config.ogygia.nebula.enable {
      key = lib.mkForce "/data/nebula/host.key";
    };

    # Pin the nebula service user to the id the reused key is already owned by
    # (the old nebula-jakehillion allocation), avoiding a chown and UID drift.
    users.users.nebula-ogygia = lib.mkIf config.ogygia.nebula.enable {
      uid = config.ids.uids.nebula-ogygia;
    };
    users.groups.nebula-ogygia = lib.mkIf config.ogygia.nebula.enable {
      gid = config.ids.gids.nebula-ogygia;
    };

    # On devboxes that sync the keys folder, point `ogygia nebula rekey` at the
    # synced CA private key so it can sign host certs.
    home-manager.users.${user} = lib.mkIf
      (config.custom.profiles.devbox && config.custom.syncthing.enable)
      {
        home.sessionVariables.OGYGIA_NEBULA_CA_KEY = caKeyTarget;
      };

    nix.settings = {
      trusted-public-keys = [
        "nix-builder-boron-260125:rYsNk2FjznUnYDLjgnQJL8U+NM2XTDwK5Z9xsOTDH98=" # deprecated as of 26/04/2026
        "nix-builder-slider-260210:A+ijnja8EoaWXElfqbo3h9y8lJbF21p717gZkAHhYQ0=" # deprecated as of 26/04/2026

        "boron-260426:Y5ndbb3OWR2hOQqC/BQKe1z2kFz9u8oLHnx22GPmKEM="
        "slider-260426:X+O6qmXb806017xciFOECVRxwNCKsMSp1nZlH4KcFpE="
      ];
      fallback = true;
      connect-timeout = 15;
    };
  };
}
