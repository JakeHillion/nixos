{ config, pkgs, lib, ... }:

{
  imports = [
    ./bluetooth.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.05";

    networking.hostName = "gendry";
    networking.domain = "jakehillion-terminals.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.kernelParams = [
      "ip=dhcp"
    ];
    boot.initrd = {
      availableKernelModules = [ "r8169" ];
      network.enable = true;
      clevis = {
        enable = true;
        useTang = true;
        devices."root".secretFile = "/data/disk_encryption.jwe";
      };
    };

    custom.defaults = true;

    ## Custom scheduler
    custom.sched_ext.enable = true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_rsa"
        ".ssh/id_ecdsa"
      ];
      userExtraDirs.jake = [
        ".local/share/PrismLauncher"
      ];
    };

    ## Enable ZRAM swap to help with root on tmpfs
    zramSwap = {
      enable = true;
      memoryPercent = 200;
      algorithm = "zstd";
    };

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.awesome.enable = true;

    ## Resilio
    custom.resilio.enable = true;

    services.resilio.deviceName = "gendry.jakehillion-terminals";
    services.resilio.directoryRoot = "/data/sync";
    services.resilio.storagePath = "/data/sync/.sync";

    custom.resilio.folders =
      let
        folderNames = [
          "dad"
          "joseph"
          "projects"
          "resources"
          "sync"
        ];
        mkFolder = name: {
          name = name;
          secret = {
            name = "resilio/plain/${name}";
            file = ../../secrets/resilio/plain/${name}.age;
          };
        };
      in
      builtins.map (mkFolder) folderNames;

    ## Tailscale
    age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".file = ../../secrets/tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk".path;
    };

    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];

    ## Graphics
    boot.initrd.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
    };
    users.users."${config.custom.user}" = {
      packages = with pkgs; [
        prismlauncher
      ];
    };

    ## Networking
    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
  };
}
