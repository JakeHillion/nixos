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
      network.enable = true;
      availableKernelModules = [ cfg.networkingModule ];

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
