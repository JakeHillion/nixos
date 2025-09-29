{ config, lib, pkgs, ... }:

let
  cfg = config.custom.home.nix-trusted-settings;
in
{
  options.custom.home.nix-trusted-settings = {
    enable = lib.mkEnableOption "nix trusted settings service";

    substituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of trusted substituters to add to nix configuration";
      example = [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
    };

    trustedPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of trusted public keys for substituters";
      example = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users."${config.custom.user}" = {
      home.activation.nix-trusted-settings =
        let
          trustedSettings = {
            "extra-substituters" = lib.listToAttrs (map (s: { name = s; value = true; }) cfg.substituters);
            "extra-trusted-public-keys" = lib.listToAttrs (map (k: { name = k; value = true; }) cfg.trustedPublicKeys);
          };
          trustedSettingsFile = pkgs.writeText "trusted-settings.json" (builtins.toJSON trustedSettings);
        in
        ''
          mkdir -p "$HOME/.local/share/nix"
          ${pkgs.coreutils}/bin/cp -n "${trustedSettingsFile}" "$HOME/.local/share/nix/trusted-settings.json"
        '';
    };
  };
}
