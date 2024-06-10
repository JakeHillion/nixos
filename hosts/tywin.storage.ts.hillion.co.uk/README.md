# tywin.storage.ts.hillion.co.uk

Additional installation step for Clevis/Tang:

    $ echo -n $DISK_ENCRYPTION_PASSWORD | clevis encrypt sss "$(cat /etc/nixos/hosts/tywin.storage.ts.hillion.co.uk/clevis_config.json)" >/mnt/disk_encryption.jwe
    $ sudo chown root:root /mnt/disk_encryption.jwe
    $ sudo chmod 0400 /mnt/disk_encryption.jwe
