{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-smh11ssli-epyc7k62
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.profiles.devbox = true;
    custom.tang.enable = true;
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Impermanence
    custom.impermanence = {
      enable = true;
      users.jake = {
        files = [
          ".ssh/id_rsa"
          ".ssh/id_ecdsa"
        ];
        directories = [
          ".local/share/patatt"
        ];
      };
    };

    ## Run latest kernel for sched_ext development
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Lockless peek patch for sched_ext testing
    boot.kernelPatches = [{
      name = "scx_lockless_peek";
      patch = ../../patches/kernel/scx_lockless_peek.patch;
    }];

    # Allow performing emulated builds in QEMU
    boot.binfmt.emulatedSystems = [
      "aarch64-linux"
      "armv7l-linux"
    ];

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

    ### Mount tracefs to enable tools like scxtop
    fileSystems."/sys/kernel/tracing" = {
      device = "tracefs";
      fsType = "tracefs";
    };

    networking = {
      useDHCP = false;

      defaultGateway.address = "10.64.50.1";

      interfaces = {
        eth0 = {
          ipv4 = {
            addresses = [{
              address = "10.64.50.20";
              prefixLength = 24;
            }];
          };
          mtu = 9000;
        };
      };
    };
  };
}
