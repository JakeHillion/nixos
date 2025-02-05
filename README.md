# nixos

### Building Raspberry Pi images

Raspberry Pi images that support headless SSH can be built as follows:

    nix build '.#nixosConfigurations."iceman.tick.neb.jakehillion.me".config.formats.sd-aarch64'

Although this will have some support for Nebula it will not be authenticated without further setup. This is because each device generates its own signing key that still needs to be signed by the CA.

This command should be run on a Linux machine with an aarch64 processor or binfmt misc support (`gendry.jakehillion-terminals` and `merlin.rig` at the time of writing). When creating Pi images you might need to comment out or update the existing file system UUID.

### Building on another system

Some systems are incapable of rebuilding by themselves, the prime example being that the Raspberry Pi 5 is unable to build its kernel. Currently I have no centralised build process so we don't have signed images.

    STORE_PATH=`nix build --no-link --print-out-paths '.#nixosConfigurations."sodium.pop.neb.jakehillion.me".config.system.build.toplevel'`
    nix-store --export $(nix-store --query --requisites $STORE_PATH) | zstd > closure.nar.zst
    cat closure.nar.zst | ssh sodium.pop.neb.jakehillion.me sh -c 'unzstd | sudo nix-store --import'

Then use `update` or `nixos-rebuild` as normal on the host (provided it can evaluate the Nix).
