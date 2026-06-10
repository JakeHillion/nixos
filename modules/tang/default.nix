{ config, pkgs, lib, ... }:

let
  cfg = config.custom.tang;
in
{
  options.custom.tang = {
    enable = lib.mkEnableOption "tang";

    networkingModule = lib.mkOption {
      type = lib.types.str;
    };

    secretFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };

    devices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd = {
      availableKernelModules = [ cfg.networkingModule ];

      # Configure systemd-networkd directly in initrd. We don't go via
      # boot.initrd.network.enable because that auto-translates the full
      # stage 2 networking.interfaces.* into boot.initrd.systemd.network,
      # which doesn't tolerate stage 2 route schemas (e.g. cyclone's
      # cellular VLAN).
      systemd.network = {
        enable = true;
        # Fallback DHCP on the tang interface. Hosts that set a static
        # `ip=...` kernel parameter get a higher-priority 91-*.network from
        # systemd-network-generator that wins over this 99-*.
        networks."99-tang-dhcp" = {
          matchConfig.Driver = cfg.networkingModule;
          networkConfig.DHCP = "yes";
        };
      };

      clevis = {
        enable = true;
        useTang = true;

        devices = builtins.listToAttrs (builtins.map
          (dev: {
            name = dev;
            value = { secretFile = cfg.secretFile; };
          })
          cfg.devices);
      };
    };
  };
}
