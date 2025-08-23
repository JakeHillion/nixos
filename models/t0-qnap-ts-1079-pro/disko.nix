{
  disko.devices = {
    disk = {
      usb = {
        type = "disk";
        device = "/dev/disk/by-path/pci-0000:00:1d.0-usb-0:1.1:1.0-scsi-0:0:0:0";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "100%";
              type = "EF00"; # EFI boot partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
          };
        };
      };
      one = {
        type = "disk";
        device = "/dev/disk/by-path/pci-0000:06:00.0-ata-1.0";
        content = {
          type = "gpt";
          partitions = {
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
                discardPolicy = "both";
              };
            };

            osd-db-0 = {
              size = "40G";
            };

            osd-db-1 = {
              size = "40G";
            };

            osd-db-2 = {
              size = "40G";
            };

            osd-db-3 = {
              size = "40G";
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
        device = "/dev/disk/by-path/pci-0000:06:00.0-ata-2.0";
        content = {
          type = "gpt";
          partitions = {
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
                discardPolicy = "both";
              };
            };

            osd-db-4 = {
              size = "40G";
            };

            osd-db-5 = {
              size = "40G";
            };

            osd-db-6 = {
              size = "40G";
            };

            osd-db-7 = {
              size = "40G";
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
