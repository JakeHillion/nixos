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
    # Trial ogygia-updated here in place of the legacy custom.auto_updater
    # (the pull-based daemon, control socket, and canaries replace the
    # timer-driven jj-on-/etc/nixos updater enabled fleet-wide by defaults).
    custom.auto_updater.enable = lib.mkForce false;
    # The interactive `update` script is superseded by `ogygia update` and
    # `ogygia update canary`; drop it here (it's on fleet-wide via custom.shell).
    custom.shell.update_scripts.enable = lib.mkForce false;
    ogygia.updated.enable = true;

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
