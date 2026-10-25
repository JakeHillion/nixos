{ config, lib, ... }:

# Shared configuration for every castaway: a fleet member with no NixOS
# configuration, such as a Mac running the Ogygia app, that takes only its
# Nebula config from this repo. Castaways evaluate this in place of the NixOS
# module tree, so it may only use modules that depend on nothing NixOS
# provides.

{
  imports = [ ../ogygia/fleet.nix ];

  options = {
    # ogygia declares this in its NixOS module, which castaways don't evaluate.
    ogygia.domain = lib.mkOption {
      type = lib.types.str;
    };

    custom.syncthing.enable = lib.mkEnableOption "syncthing";
  };

  config = {
    ogygia.nebula = lib.mkIf config.custom.syncthing.enable (import ../syncthing/nebula.nix);
  };
}
