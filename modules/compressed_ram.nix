{ pkgs, lib, config, ... }:

let
  cfg = config.custom.compressed_ram;
in
{
  options.custom.compressed_ram = {
    enable = lib.mkEnableOption "compressed_ram";

    zswapMaxPoolPercent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
    };
  };

  config = lib.mkIf cfg.enable (
    let
      hasSwap = config.swapDevices != [ ];
    in
    {
      zramSwap = lib.mkIf (!hasSwap) {
        enable = true;
        memoryPercent = lib.mkOverride 51 200;
        algorithm = "zstd";
      };

      boot.kernelParams = lib.mkIf hasSwap [
        "zswap.enabled=1"
        "zswap.compressor=zstd"
        "zswap.max_pool_percent=${toString cfg.zswapMaxPoolPercent}"
      ];
    }
  );
}

