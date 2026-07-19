{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-minisforum-ms-a2
  ];

  config = {
    system.stateVersion = "25.11";

    custom.defaults = true;
    custom.profiles.devbox = true;

    ogygia.nebula = {
      groups = [ "legacy-full-access" ];
      pubKey = ''
        -----BEGIN NEBULA X25519 PUBLIC KEY-----
        dgwdcpGpB33ngTIedUERJYgeEyHmyzkHNGS9oT2SQC8=
        -----END NEBULA X25519 PUBLIC KEY-----
      '';
    };

    ## Automatic updates
    # ogygia-updated is the sole updater on this host; turn off the others so
    # nothing else races it to drive the system profile.
    ogygia.updated.enable = true;
    custom.auto_updater.enable = lib.mkForce false;
    custom.shell.update_scripts.enable = lib.mkForce false;
    # Substitute the store-warm closure before building: the nixos-<fqdn> check
    # is this host's toplevel with the configurationRevision zeroed, so it is
    # identical to the real build bar the revision stamp and substitutes
    # wholesale. If the cache lacks it the daemon skips the cycle rather than
    # building the full closure locally.
    ogygia.updated.settings.build.prefetch_attr =
      "checks.${pkgs.stdenv.hostPlatform.system}.\"nixos-${config.networking.fqdn}\"";

    custom.tang.enable = true;
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_rsa"
        ".ssh/id_ecdsa"
      ];
    };

    boot.kernelPackages = pkgs.linuxPackages_latest;

    ## Syncthing
    custom.syncthing = {
      enable = true;
      baseDir = "/data/users/jake/sync";
    };

    ## General usability
    ### Make podman available for dev tools such as act
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
      };
    };
    users.users.jake.extraGroups = [ "podman" ];

    networking = {
      useDHCP = false;

      defaultGateway.address = "10.64.50.1";

      interfaces = {
        enp5s0f1np1 = {
          ipv4 = {
            addresses = [{
              address = "10.64.50.30";
              prefixLength = 24;
            }];
          };
          mtu = 9000;
        };
      };
    };
  };
}
