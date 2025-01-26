# nixos

### Building Raspberry Pi images

Raspberry Pi images that support Nebula and headless SSH can be built using a command. It is easiest to run this command on AArch64 on Linux, such as within a Linux VM or Docker container on an M1 Mac.

    docker run -v $PWD:/src -it --rm nixos/nix:latest /bin/sh
    nix-env -f https://github.com/nix-community/nixos-generators/archive/master.tar.gz -i
    cd /src
    nixos-generate -f sd-aarch64-installer --system aarch64-linux -c hosts/microserver.home.neb.jakehillion.me/default.nix
    cp SOME_OUTPUT out.img.zst

Alternatively, a Raspberry Pi image with headless SSH can be easily built using the logic in [this repo](https://github.com/Robertof/nixos-docker-sd-image-builder/tree/master).
