{
  disko.devices = {
    disk = {
      one = {
        type = "disk";
        device = "/dev/disk/by-path/pci-0000:00:17.0-ata-1.0";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot0";
                mountOptions = [ "umask=0077" ];
              };
            };

            swap = {
              size = "16G";
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
              };
            };
          };
        };
      };
      two = {
        type = "disk";
        device = "/dev/disk/by-path/pci-0000:00:17.0-ata-2.0";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot1";
                mountOptions = [ "umask=0077" ];
              };
            };

            swap = {
              size = "16G";
              content = {
                type = "swap";
                randomEncryption = true;
                discardPolicy = "both";
              };
            };

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
