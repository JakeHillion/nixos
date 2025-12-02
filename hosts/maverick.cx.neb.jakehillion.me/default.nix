{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-minisforum-ms-a2
  ];

  config = {
    system.stateVersion = "25.11";

    custom.defaults = true;
    custom.profiles.devbox.enable = true;
    custom.tang.enable = true;
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Impermanence
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
        enp3s0 = {
          ipv4 = {
            addresses = [{
              address = "10.64.50.26";
              prefixLength = 24;
            }];
          };
          mtu = 9000;
        };
      };
    };
  };
}
