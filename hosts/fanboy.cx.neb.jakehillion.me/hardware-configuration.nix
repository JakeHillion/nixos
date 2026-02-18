{
  disko.devices = {
    disk = {
      one = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            swap = {
              size = "32G";
              content = {
                type = "swap";
                randomEncryption = true;
                discardPolicy = "both";
              };
            };

            disk0-crypt = {
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

    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [
          "mode=755"
          "size=100%"
        ];
      };
    };
  };
}
