#!/usr/bin/env nix-shell
#!nix-shell -i bash -p restic rsync
set -e

HOST="restic.neb.jakehillion.me"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

rsync -ar --no-perms --delete-after --rsync-path='sudo -u restic rsync' --progress $HOST:/practical-defiant-coffee/backups/restic/1.6T/ restic/1.6T

echo 'checking 1.6T'
restic -r restic/1.6T check --read-data-subset=25%

touch last_synced
