{ config, pkgs, lib, ... }:

let
  cfg = config.custom.sched_ext;
in
{
  options.custom.sched_ext = {
    enable = lib.mkEnableOption "sched_ext";

    scheduler = lib.mkOption {
      description = "Scheduler to activate";
      type = with lib.types; nullOr (enum [
        "scx_lavd"
      ]);
      default = null;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [{
        assertion = config.boot.kernelPackages.kernelAtLeast "6.12";
        message = "sched_ext requires a kernel >=6.12";
      }];

      boot.kernelPackages =
        if pkgs.linuxPackages.kernelAtLeast "6.12" then pkgs.linuxPackages
        else if pkgs.linuxPackages_latest.kernelAtLeast "6.12" then pkgs.linuxPackages_latest
        else if pkgs.unstable.linuxPackages_latest.kernelAtLeast "6.12" then pkgs.unstable.linuxPackages_latest
        else pkgs.unstable.linuxPackages_testing;
    }

    (lib.mkIf (cfg.scheduler == "scx_lavd") {
      services.scx = {
        enable = true;
        scheduler = "scx_lavd";
        package = pkgs.runCommand "scx_lavd" { } ''
          mkdir -p $out/bin
          install ${pkgs.scx.rustscheds}/bin/scx_lavd $out/bin
        '';
      };
    })
  ]);
}

