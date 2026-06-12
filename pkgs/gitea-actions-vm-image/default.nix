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
, dpkg
, closureInfo
, gitea-actions-runner
, nodejs_24
,
}:

let
  ubuntuImg = fetchurl {
    url = "https://cloud-images.ubuntu.com/releases/26.04/release-20260421/ubuntu-26.04-server-cloudimg-amd64.img";
    hash = "sha256-jtIoyfCKUBIvpyMHYj2fiNkgm6JufoSe3VhPpnXjSGM=";
  };

  # qemu-guest-agent isn't in the Ubuntu cloud image manifest, so we pull the
  # .deb from the archive and extract it directly. liburing2 is a dependency
  # that's also missing from the cloud image (libc6/libudev1/libglib2/libnuma1
  # are already present). Versions/hashes from
  # http://archive.ubuntu.com/ubuntu/dists/resolute/{universe,main}/binary-amd64/Packages.gz.
  qemuGuestAgentDeb = fetchurl {
    url = "http://archive.ubuntu.com/ubuntu/pool/universe/q/qemu/qemu-guest-agent_10.2.1+ds-1ubuntu3_amd64.deb";
    hash = "sha256-YTzGw0OVvmy4k1MKsYJV8uKoEVuLuJTHBXTOR44d2mc=";
  };
  liburing2Deb = fetchurl {
    url = "http://archive.ubuntu.com/ubuntu/pool/main/libu/liburing/liburing2_2.14-1_amd64.deb";
    hash = "sha256-wPHtVdLqpuXRIkUTt4fHE0jGq5g+nEF4pBen/6w6igA=";
  };

  # Extra tools to expose on the in-VM PATH alongside act_runner. Each package's
  # bin/* entries get symlinked into /usr/local/bin/. Node 24 is the floor —
  # GitHub Actions removes Node 20 from its hosted runners on 2026-09-16, and
  # most JS-based actions (actions/checkout, etc.) refuse to run without it.
  extraPaths = [ nodejs_24 ];
  toolPaths = [ gitea-actions-runner ] ++ extraPaths;

  runnerClosure = closureInfo { rootPaths = toolPaths; };
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

  nativeBuildInputs = [ util-linux e2fsprogs dpkg ];

  meta = with lib; {
    description = "Ubuntu 26.04 LTS qcow2 customised for ephemeral Gitea Actions runners";
    platforms = [ "x86_64-linux" ];
  };
} ''
  set -eu

  mkdir -p /mnt
  mount /dev/vda1 /mnt

  # Add a `runner` user matching GitHub-hosted runners (UID/GID 1001, HOME
  # /home/runner, locked password). Most actions assume that name and that
  # HOME, and `sudo apt-get install …` is near-universal in workflows. Bake
  # the user into the image so it doesn't need recreating on every boot.
  echo 'runner:x:1001:1001:Runner:/home/runner:/bin/bash' >> /mnt/etc/passwd
  echo 'runner:x:1001:'                                  >> /mnt/etc/group
  echo 'runner:!:19500:0:99999:7:::'                     >> /mnt/etc/shadow
  echo 'runner:!::'                                      >> /mnt/etc/gshadow

  install -d -m 0755 -o 1001 -g 1001 /mnt/home/runner
  install -d -m 0755 -o 1001 -g 1001 /mnt/var/lib/gitea-runner
  install -d -m 0755 -o 1001 -g 1001 /mnt/var/lib/gitea-runner-jobs

  install -Dm440 /dev/stdin /mnt/etc/sudoers.d/runner <<'EOF'
  runner ALL=(ALL:ALL) NOPASSWD:ALL
  Defaults env_keep += "DEBIAN_FRONTEND"
  EOF

  # Copy the act_runner Nix closure into the image's /nix/store. The
  # gitea-actions-runner binary is dynamically linked against Nix-store
  # glibc, so we need its full closure (glibc, tzdata, iana-etc, mailcap)
  # alongside it for the binary to resolve at runtime.
  mkdir -p /mnt/nix/store
  while read -r storePath; do
    cp -a "$storePath" /mnt/nix/store/
  done < ${runnerClosure}/store-paths

  # Stable user-space entry points: symlink every tool's bin/* into
  # /usr/local/bin so the runner unit and the actions it spawns find them
  # without needing /nix/store on PATH.
  mkdir -p /mnt/usr/local/bin
  for pkg in ${toString toolPaths}; do
    for f in "$pkg"/bin/*; do
      [ -e "$f" ] || continue
      ln -sf "$f" "/mnt/usr/local/bin/$(basename "$f")"
    done
  done

  # systemd unit for the runner. The per-VM credentials (.runner +
  # config.yaml) are placed in /var/lib/gitea-runner by cloud-init's
  # write_files from the instance user-data before the unit starts.
  install -Dm644 ${./runner.service} /mnt/etc/systemd/system/gitea-runner.service

  # Periodic cycle timer — see runner-cycle.{service,timer} for rationale.
  # Recovers act_runner from the "unregistered runner" wedge by SIGTERMing
  # the main process; in-flight jobs drain via runner.shutdown_timeout.
  install -Dm644 ${./runner-cycle.service} /mnt/etc/systemd/system/gitea-runner-cycle.service
  install -Dm644 ${./runner-cycle.timer}   /mnt/etc/systemd/system/gitea-runner-cycle.timer

  # Wire enable for our service. cloud-init.target.wants (rather than
  # multi-user.target.wants) so we order strictly after cloud-final.service.
  mkdir -p /mnt/etc/systemd/system/cloud-init.target.wants
  ln -sf /etc/systemd/system/gitea-runner.service \
    /mnt/etc/systemd/system/cloud-init.target.wants/gitea-runner.service

  # Enable the cycle timer via timers.target.wants.
  mkdir -p /mnt/etc/systemd/system/timers.target.wants
  ln -sf /etc/systemd/system/gitea-runner-cycle.timer \
    /mnt/etc/systemd/system/timers.target.wants/gitea-runner-cycle.timer

  # Install qemu-guest-agent (and its only missing dependency, liburing2) so
  # the host can probe in-guest state via QGA — used both for the graceful-
  # shutdown handshake and for the nixos-rebuild idle-restart logic. Cloud
  # image manifest only includes the deps libc6/libudev1/libglib2/libnuma1;
  # we extract the .debs directly with dpkg-deb to avoid running maintainer
  # scripts inside the image. The enable symlink replaces the postinst's
  # `systemctl enable`.
  for deb in ${qemuGuestAgentDeb} ${liburing2Deb}; do
    dpkg-deb --extract "$deb" /mnt
  done
  mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
  ln -sf /lib/systemd/system/qemu-guest-agent.service \
    /mnt/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service

  # Restrict cloud-init to the datasources we actually boot on so it doesn't
  # waste boot time scanning other providers' metadata endpoints: NoCloud for
  # local QEMU (cidata ISO with static network-config) and GCE for burst VMs
  # (metadata server). On every substrate the per-VM runner credentials
  # arrive as user-data (#cloud-config write_files).
  install -Dm644 /dev/stdin /mnt/etc/cloud/cloud.cfg.d/99-runner.cfg <<'EOF'
  datasource_list: [ NoCloud, GCE, None ]
  EOF

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
