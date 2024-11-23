{ config, pkgs, lib, ... }:

let
  cfg = config.custom.kernel;
in
{
  options.custom.kernel = {
    enable = lib.mkEnableOption "kernel";

    requiredVersions = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.mkIf (cfg.enable && cfg.requiredVersions != [ ]) {
    assertions = builtins.map
      (v: {
        assertion = config.boot.kernelPackages.kernelAtLeast v;
        message = "a kernel version >=${v} is requested but can't be satisfied!";
      })
      cfg.requiredVersions;

    boot.kernelPackages = lib.mkOverride 999 (
      let
        maxKernelVersion = a: b: if (lib.versionOlder a b) then b else a;
        requiredKernelVersion = lib.lists.foldl maxKernelVersion "0.0.0" cfg.requiredVersions;
      in
      if pkgs.linuxPackages.kernelAtLeast requiredKernelVersion then pkgs.linuxPackages
      else if pkgs.linuxPackages_latest.kernelAtLeast requiredKernelVersion then pkgs.linuxPackages_latest
      else if pkgs.unstable.linuxPackages_latest.kernelAtLeast requiredKernelVersion then pkgs.unstable.linuxPackages_latest
      else pkgs.unstable.linuxPackages_testing
    );
  };
}
