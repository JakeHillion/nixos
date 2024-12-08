#!/usr/bin/env nix-shell
#!nix-shell -i bash -p restic rsync
set -e

HOST="restic.ts.hillion.co.uk"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

rsync -ar --no-perms --delete-after --rsync-path='sudo -u restic rsync' --progress $HOST:/practical-defiant-coffee/backups/restic/128G/ restic/128G

echo 'checking 128G'
restic -r restic/128G check --read-data-subset=25%

touch last_synced
