# boron.cx.neb.jakehillion.me

Additional installation step for Clevis/Tang:

    $ echo -n $DISK_ENCRYPTION_PASSWORD | clevis encrypt sss "$(nix eval --json '/etc/nixos#nixosConfigurations."boron.cx.neb.jakehillion.me".config.ogygia.clevis.spec')" >/mnt/data/disk_encryption.jwe
    $ sudo chown root:root /mnt/data/disk_encryption.jwe
    $ sudo chmod 0400 /mnt/data/disk_encryption.jwe
