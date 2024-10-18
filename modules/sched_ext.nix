{ config, pkgs, lib, ... }:

let
  cfg = config.custom.sched_ext;
in
{
  options.custom.sched_ext = {
    enable = lib.mkEnableOption "sched_ext";
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.boot.kernelPackages.kernelAtLeast "6.12";
      message = "sched_ext requires a kernel >=6.12";
    }];

    boot.kernelPackages = if pkgs.linuxPackages.kernelAtLeast "6.12" then pkgs.linuxPackages else (if pkgs.linuxPackages_latest.kernelAtLeast "6.12" then pkgs.linuxPackages_latest else pkgs.unstable.linuxPackages_testing);

    environment.systemPackages = with pkgs; [ unstable.scx_layered scx_lavd ];
  };
}

