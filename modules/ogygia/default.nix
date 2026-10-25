{ pkgs, lib, config, ... }:

let
  cfg = config.custom.ogygia;

  user = config.custom.user;

  # Operator CA private key location for `ogygia nebula rekey`. Lives in the
  # synced `sync` folder (via the /home/<user>/local impermanence symlink).
  caKeyTarget = "${config.users.users.${user}.home}/local/sync/sync/keys/nebula-ca-2527.key";
in
{
  imports = [
    ./fleet.nix
    ./irisd.nix
  ];

  options.custom.ogygia = {
    enable = lib.mkEnableOption "ogygia";
  };

  config = lib.mkIf cfg.enable {
    ogygia = {
      enable = true;

      gitRemoteUrl = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";

      etcd = {
        endpoints = config.custom.services.etcd.endpoints;
      };

      # Fleet-wide configuration for the ogygia-managed Nebula overlay, which
      # replaces the legacy custom.nebula mesh. Enabled by default; hosts whose
      # keypair hasn't been grabbed yet opt out in their own config.
      nebula = {
        enable = true;

        # etcd-client follows hostinfod, the etcd publisher, so a host that
        # disables it (fanboy) gets no etcd access.
        groups = lib.optional config.ogygia.hostinfod.enable "etcd-client";
      };
    };

    environment.systemPackages = [ pkgs.ogygia ];

    ogygia.updated = {
      enable = true;

      settings = {
        # Warm the store from the binary cache before building: the nixos-<fqdn>
        # check is this host's toplevel with the configurationRevision zeroed, so
        # it is identical to the real build bar the revision stamp and substitutes
        # wholesale. Pointing every updated host at it keeps CI and the
        # ogygia-irisd peer cache exercised; a host that cannot substitute it
        # skips the cycle rather than building the whole closure locally.
        build.prefetch_attr = lib.mkDefault
          "checks.${pkgs.stdenv.hostPlatform.system}.\"nixos-${config.networking.fqdn}\"";

        # Point the daemon's clone and canary record straight at persistent
        # storage. Persisting the default /var/lib location with a bind mount
        # instead makes that mount a RequiresMountsFor dependency of the service;
        # switch-to-configuration restarts the mount during activation and the
        # hard dependency tears the daemon down mid-update — the very update it is
        # running. A plain directory has no mount unit and no such dependency.
        state_dir = lib.mkIf config.custom.impermanence.enable
          "${config.custom.impermanence.base}/system/var/lib/ogygia-updated";
      };
    };

    # The persistent state_dir supersedes the unit's /var/lib StateDirectory;
    # drop it so systemd neither creates an unused tmpfs directory nor adds the
    # RequiresMountsFor that reintroduces the dependency we are removing.
    systemd.services.ogygia-updated.serviceConfig.StateDirectory =
      lib.mkIf (config.ogygia.updated.enable && config.custom.impermanence.enable) (lib.mkForce "");

    # StateDirectory used to guarantee the state directory existed with a known
    # owner and mode; recreate that guarantee for the persistent path so it is
    # in place before the daemon starts rather than left to its first clone.
    systemd.tmpfiles.rules = lib.mkIf (config.ogygia.updated.enable && config.custom.impermanence.enable)
      [ "d ${config.custom.impermanence.base}/system/var/lib/ogygia-updated 0700 root root - -" ];

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
        "iceman-260729:cyLIDCaq8nrDa+IjVbWthe5CC73mzklvinulnvUyMMs="
      ];
      fallback = true;
      connect-timeout = 15;
    };
  };
}
