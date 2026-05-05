# Builds a customised Ubuntu 26.04 LTS qcow2 in the Nix store with the Gitea
# Actions runner binary and a boot-time systemd unit that runs act_runner
# ephemerally (one job, then power off).
#
# The base image is fetched as a fixed-output derivation. It is then mounted
# inside a vmTools.runInLinuxVM build VM, customised, and re-emitted at $out.
# Partition + filesystem auto-grow at first boot via cloud-initramfs-growroot
# (in the initramfs) and systemd-growfs (via the rootfs mount option), so the
# overlay's larger virtual size at runtime is picked up without manual resize.
{ lib
, runCommand
, fetchurl
, vmTools
, qemu
, util-linux
, e2fsprogs
, closureInfo
, gitea-actions-runner
,
}:

let
  ubuntuImg = fetchurl {
    url = "https://cloud-images.ubuntu.com/releases/26.04/release-20260421/ubuntu-26.04-server-cloudimg-amd64.img";
    hash = "sha256-jtIoyfCKUBIvpyMHYj2fiNkgm6JufoSe3VhPpnXjSGM=";
  };

  runnerClosure = closureInfo { rootPaths = [ gitea-actions-runner ]; };
in
vmTools.runInLinuxVM (runCommand "gitea-actions-vm-image"
{
  diskImage = "image.qcow2";
  memSize = 1024;

  preVM = ''
    mkdir -p $out
    cp ${ubuntuImg} image.qcow2
    chmod +w image.qcow2
  '';

  postVM = ''
    mv image.qcow2 $out/image.qcow2
  '';

  nativeBuildInputs = [ util-linux e2fsprogs ];

  meta = with lib; {
    description = "Ubuntu 26.04 LTS qcow2 customised for ephemeral Gitea Actions runners";
    platforms = [ "x86_64-linux" ];
  };
} ''
  set -eu

  mkdir -p /mnt
  mount /dev/vda1 /mnt

  # Copy the act_runner Nix closure into the image's /nix/store. The
  # gitea-actions-runner binary is dynamically linked against Nix-store
  # glibc, so we need its full closure (glibc, tzdata, iana-etc, mailcap)
  # alongside it for the binary to resolve at runtime.
  mkdir -p /mnt/nix/store
  while read -r storePath; do
    cp -a "$storePath" /mnt/nix/store/
  done < ${runnerClosure}/store-paths

  # Stable user-space entry point for the systemd unit.
  mkdir -p /mnt/usr/local/bin
  ln -sf ${gitea-actions-runner}/bin/act_runner /mnt/usr/local/bin/act_runner

  # systemd unit + startup script for the runner.
  install -Dm644 ${./runner.service}    /mnt/etc/systemd/system/gitea-runner.service
  install -Dm755 ${./runner-startup.sh} /mnt/usr/local/sbin/gitea-runner-startup

  # Wire enable for our service.
  mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/gitea-runner.service \
    /mnt/etc/systemd/system/multi-user.target.wants/gitea-runner.service

  # Disable cloud-init's user-data processing (we configure everything statically).
  # cloud-initramfs-growroot stays — that's a separate package in the initrd
  # that auto-grows the rootfs partition to fit the runtime overlay's larger
  # virtual disk.
  touch /mnt/etc/cloud/cloud-init.disabled

  # Fresh machine-id per VM boot (systemd will regenerate on first boot).
  : > /mnt/etc/machine-id

  # Disable snapd — slow, not needed.
  rm -f /mnt/etc/systemd/system/multi-user.target.wants/snapd.service \
        /mnt/etc/systemd/system/multi-user.target.wants/snapd.seeded.service \
        /mnt/etc/systemd/system/multi-user.target.wants/snapd.socket \
        /mnt/etc/systemd/system/sockets.target.wants/snapd.socket

  umount /mnt
  sync
'')
