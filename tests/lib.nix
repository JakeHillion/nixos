# Test helper library for NixOS module evaluation
{ pkgs, lib, inputs, system }:

let
  mkSystem = import ../lib/mkSystem.nix { inherit inputs; };

  # Minimal base config to satisfy NixOS requirements
  baseConfig = { config, ... }: {
    boot.loader.grub.device = "nodev";
    fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
    fileSystems."/data" = { device = "/dev/sda2"; fsType = "ext4"; };
    fileSystems."/cache" = { device = "/dev/sda3"; fsType = "ext4"; };

    networking.hostName = "test";
    networking.domain = "example.com";

    nixpkgs.hostPlatform = system;

    custom.defaults = true;

    home-manager.users.root = { };
    home-manager.users.jake = { };
  };

in
{
  # Evaluate a NixOS configuration with identical modules to nixosConfigurations
  evalConfig = { modules ? [ ] }:
    lib.nixosSystem {
      inherit system;
      specialArgs = inputs;
      modules = mkSystem.modules inputs.home-manager ++ [ baseConfig ] ++ modules;
    };
}
