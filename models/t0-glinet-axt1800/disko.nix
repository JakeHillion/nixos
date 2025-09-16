{
  disko.devices = {
    disk.disk0 = {
      type = "disk";
      device = "mmcblk0";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";

              subvolumes = {
                "/impermanence_root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
                "/data" = {
                  mountpoint = "/data";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
