{
  disko.devices = {
    disk = {
      disk0 = {
        type = "disk";
        device = "/dev/nvme0n1";
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

            disk0-crypt = {
              size = "100%";
              content = {
                type = "luks";
                name = "disk0-crypt";
                settings = {
                  allowDiscards = true;
                };
              };
            };

            swap = {
              size = "64G";
              content = {
                type = "swap";
                randomEncryption = true;
                discardPolicy = "both";
              };
            };
          };
        };
      };

      disk1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            disk1-crypt = {
              size = "100%";
              content = {
                type = "luks";
                name = "disk1-crypt";
                settings = {
                  allowDiscards = true;
                };

                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-d raid1"
                    "/dev/mapper/disk0-crypt"
                  ];

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

            swap = {
              size = "64G";
              content = {
                type = "swap";
                randomEncryption = true;
                discardPolicy = "both";
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
