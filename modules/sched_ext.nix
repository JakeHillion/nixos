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

    custom.kernel.requiredVersions = [ "6.12" ];
    environment.systemPackages = with pkgs; [ unstable.scx.layered unstable.scx.lavd ];
  };
}

