let
  ssd = crypt: {
    type = "gpt";
    partitions = {
      swap = {
        size = "16G";
        content = {
          type = "swap";
          randomEncryption = true;
          discardPolicy = "both";
        };
      };

      ${crypt} = {
        size = "100%";
        content = {
          type = "luks";
          name = crypt;
          settings = {
            allowDiscards = true;
          };
          content = {
            type = "lvm_pv";
            vg = "pool";
          };
        };
      };
    };
  };
in
{
  disko.devices = {
    disk = {
      emmc = {
        type = "disk";
        device = "/dev/disk/by-id/mmc-DV4064_0xb45e6932";
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

            disk2-crypt = {
              size = "100%";
              content = {
                type = "luks";
                name = "disk2-crypt";
                settings = {
                  allowDiscards = true;
                };
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/nix";
                  mountOptions = [ "noatime" ];
                };
              };
            };
          };
        };
      };

      sata = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WDS100T1R0B-68A4Z0_23133Y800580";
        content = ssd "disk0-crypt";
      };

      nvme = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-CT1000P310SSD8_2538531AF026";
        content = ssd "disk1-crypt";
      };
    };

    lvm_vg.pool = {
      type = "lvm_vg";
      lvs.data = {
        size = "32G";
        lvm_type = "raid1";
        extraArgs = [ "--raidintegrity" "y" ];
        content = {
          type = "filesystem";
          format = "xfs";
          mountpoint = "/data";
          mountOptions = [ "noatime" ];
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
