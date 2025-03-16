#!/usr/bin/env -S nix shell nixpkgs#bash nixpkgs#clevis --command bash
set -e

TMPFILE=$(sudo mktemp)

sudo cat /data/disk_encryption.jwe | clevis decrypt | clevis encrypt sss "$(cat /etc/nixos/scripts/clevis/home_config.json)" | sudo tee $TMPFILE >/dev/null

echo "!!!!!!!!!!!!!!!!!!!!!"
echo "WARNING: clevis gives the wrong exit code, so we don't know if the file was decrypted successfully - check carefully before continuing!"
echo "!!!!!!!!!!!!!!!!!!!!!"

read -p "Do you want to overwrite this file?" yn
case $yn in
  [Yy]* ) ;;
  [Nn]* ) exit;;
  * ) echo "Invalid answer"; exit;;
esac

sudo install -m0400 $TMPFILE /data/disk_encryption.jwe
