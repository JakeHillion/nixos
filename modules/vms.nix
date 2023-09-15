{ config, lib, ... }:

{
  options = {
    boot.isVirtualMachine = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether this NixOS machine is a virtual machine running in another NixOS system.
      '';
    };

    virtualMachines = lib.mkOption {
      type = lib.types.attrsOf
        (lib.types.submodule (
          { config, options, name, ... }:
          { }
        ))
        };
    };
  }
