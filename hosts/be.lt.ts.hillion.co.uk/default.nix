{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "be";
    networking.domain = "lt.ts.hillion.co.uk";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    custom.defaults = true;
    custom.kernel.enable = true;

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_ecdsa_sk_keys"
      ];
    };

    ## WiFi
    age.secrets."wifi/be.lt.ts.hillion.co.uk".file = ../../secrets/wifi/be.lt.ts.hillion.co.uk.age;
    networking.wireless = {
      enable = true;
      secretsFile = config.age.secrets."wifi/be.lt.ts.hillion.co.uk".path;

      networks = {
        "Hillion WPA3 Network".pskRaw = "ext:HILLION_WPA3_NETWORK_PSK";
      };
    };

    ## Desktop
    custom.users.jake.password = true;
    custom.desktop.awesome.enable = true;

    ## Tailscale
    age.secrets."tailscale/be.lt.ts.hillion.co.uk".file = ../../secrets/tailscale/be.lt.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/be.lt.ts.hillion.co.uk".path;
    };

    security.sudo.wheelNeedsPassword = lib.mkForce true;

    ## Enable btrfs compression
    fileSystems."/data".options = [ "compress=zstd" ];
    fileSystems."/nix".options = [ "compress=zstd" ];
  };
}
