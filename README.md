# nixos

### Building Raspberry Pi images

Raspberry Pi images that support headless SSH can be built as follows:

    nix build '.#nixosConfigurations."iceman.tick.neb.jakehillion.me".config.formats.sd-aarch64'

Although this will have some support for Nebula it will not be authenticated without further setup. This is because each device generates its own signing key that still needs to be signed by the CA.

This command should be run on a Linux machine with an aarch64 processor or binfmt misc support (`gendry.jakehillion-terminals` and `merlin.rig` at the time of writing). When creating Pi images you might need to comment out or update the existing file system UUID.
