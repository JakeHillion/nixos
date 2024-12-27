# phoenix.st.neb.jakehillion.me

Additional installation step for Clevis/Tang:

    $ echo -n $DISK_ENCRYPTION_PASSWORD | clevis encrypt sss "$(cat /etc/nixos/hosts/phoenix.st.neb.jakehillion.me/clevis_config.json)" >/mnt/data/disk_encryption.jwe
    $ sudo chown root:root /mnt/data/disk_encryption.jwe
    $ sudo chmod 0400 /mnt/data/disk_encryption.jwe
