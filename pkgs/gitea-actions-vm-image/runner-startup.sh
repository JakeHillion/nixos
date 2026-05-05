#!/bin/sh
# Mount the read-only RUNNERSTATE disk (built by the host before VM start) and
# run act_runner once. The unit's ExecStopPost powers the VM off after exit.
set -eu

mkdir -p /etc/gitea-runner
if ! mountpoint -q /etc/gitea-runner; then
  mount -o ro /dev/disk/by-label/RUNNERSTATE /etc/gitea-runner
fi

cd /etc/gitea-runner
exec /usr/local/bin/act_runner daemon --config /etc/gitea-runner/config.yaml
