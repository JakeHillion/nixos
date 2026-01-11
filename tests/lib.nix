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

  # Normalize /nix/store paths by replacing hash and derivation name with a placeholder
  # This makes snapshots stable across dependency updates (versions change too)
  normalizeStorePaths =
    let
      normalizeString = s:
        let
          # Match /nix/store/<hash>-<name> up to the next / or end of string
          parts = builtins.split "/nix/store/[a-z0-9]{32}-[^/]+" s;
          normalize = part:
            if builtins.isList part
            then "/nix/store/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            else part;
        in
        lib.concatStrings (map normalize parts);

      go = value:
        if builtins.isString value then normalizeString value
        else if builtins.isAttrs value then lib.mapAttrs (_: go) value
        else if builtins.isList value then map go value
        else value;
    in
    go;

in
{
  # Evaluate a NixOS configuration with identical modules to nixosConfigurations
  evalConfig = { modules ? [ ] }:
    lib.nixosSystem {
      inherit system;
      specialArgs = inputs;
      modules = mkSystem.modules inputs.home-manager ++ [ baseConfig ] ++ modules;
    };

  inherit normalizeStorePaths;
}
