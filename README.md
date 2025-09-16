# nixos

### Building Raspberry Pi images

Raspberry Pi images that support headless SSH can be built as follows:

    nix build '.#nixosConfigurations."li.pop.neb.jakehillion.me".config.formats.sd-aarch64'

Although this will have some support for Nebula it will not be authenticated without further setup. This is because each device generates its own signing key that still needs to be signed by the CA.

This command should be run on a Linux machine with an aarch64 processor or binfmt misc support (`rooster.cx` and `merlin.rig` at the time of writing). When creating Pi images you might need to comment out or update the existing file system UUID.

### Building on another system

Some systems are very slow at rebuilding themselves, with one example being Boron struggling to build Mongo. There are two approaches:

**Remote builders** (builds on remote machine):

    nix build '.#nixosConfigurations."hondo.gw.neb.jakehillion.me".config.system.build.toplevel' \
        --builders 'jake@slider.pop.neb.jakehillion.me aarch64-linux /data/users/jake/.ssh/id_ecdsa'

**Manual transfer** (build locally, transfer result):

    STORE_PATH=`nix build --no-link --print-out-paths '.#nixosConfigurations."boron.cx.neb.jakehillion.me".config.system.build.toplevel'`
    nix-store --export $(nix-store --query --requisites $STORE_PATH) | zstd > closure.nar.zst
    cat closure.nar.zst | ssh boron.cx.neb.jakehillion.me sh -c 'unzstd | sudo nix-store --import'

Then use `update` or `nixos-rebuild` as normal on the host (provided it can evaluate the Nix).
