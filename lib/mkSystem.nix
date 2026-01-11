# Shared NixOS system configuration
# Used by both flake.nix for hosts and tests for evaluation
{ inputs }:

{
  # Common modules for all NixOS systems
  modules = home-manager: [
    ../modules

    inputs.agenix.nixosModules.default
    inputs.disko.nixosModules.disko
    inputs.hearthd.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
    inputs.nixos-generators.nixosModules.all-formats
    inputs.ogygia.nixosModules.default

    home-manager.nixosModules.default
    {
      home-manager.sharedModules = [
        inputs.impermanence.nixosModules.home-manager.impermanence
      ];
    }
  ];
}
