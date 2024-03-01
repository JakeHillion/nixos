#!/bin/sh
set -xe

VERSION=`curl https://gitea.hillion.co.uk/JakeHillion/nixos/raw/branch/main/flake.lock | nix run nixpkgs#jq -- -r '.nodes."nixpkgs-unstable".locked.rev'`
nix registry add nixpkgs "github:NixOS/nixpkgs/${VERSION}"
