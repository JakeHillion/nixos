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
              type = "luks";
              name = "disk0-crypt";
              settings = {
                allowDiscards = true;
              };

              content = {
                type = "btrfs";

                subvolumes = {
                  "/" = {
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
  };
}
