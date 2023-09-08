# nixos

### Building Raspberry Pi images

Raspberry Pi images that support Tailscale and headless SSH can be built using a command. It is easiest to run this command on AArch64 on Linux, such as within a Linux VM or Docker container on an M1 Mac.

    $ docker run -v $PWD:/etc/nixos -it --rm nixos/nix:latest
    # cd /etc/nixos
    # nix build .#images.microserver.home.ts.hillion.co.uk

