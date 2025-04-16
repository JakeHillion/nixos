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
                mountpoint = "/boot0";
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
              };
            };
          };
        };
      };
      two = {
        type = "disk";
        device = "/dev/nvme1n1";
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
              size = "32G";
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
              };
            };
          };
        };
      };
      three = {
        type = "disk";
        device = "/dev/nvme2n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot2";
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

            disk2-crypt = {
              size = "100%";
              content = {
                type = "luks";
                name = "disk2-crypt";
                settings = {
                  allowDiscards = true;
                };
              };
            };
          };
        };
      };
      four = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot3";
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

            disk3-crypt = {
              size = "100%";
              content = {
                type = "luks";
                name = "disk3-crypt";
                settings = {
                  allowDiscards = true;
                };

                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-d raid1"
                    "/dev/mapper/disk0-crypt"
                    "/dev/mapper/disk1-crypt"
                    "/dev/mapper/disk2-crypt"
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
