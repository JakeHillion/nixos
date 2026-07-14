{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.gitea.actions-vm;

  bridgeName = "br-runners";
  bridgeCidr = "10.108.28.0/24";
  bridgeAddress = "10.108.28.1";
  bridgePrefix = 24;
  vmIp = i: "10.108.28.${toString (10 + i)}";
  vmMac = i: "52:54:00:7e:b1:${lib.fixedWidthString 2 "0" (lib.toHexString i)}";

  instanceIds = lib.range 1 cfg.instances;

  image = pkgs.gitea-actions-vm-image;

  # Helper that runs inside ExecStart as the dynamic user. It registers a
  # fresh ephemeral runner with Gitea, builds the small RUNNERSTATE ext4
  # image consumed by the VM, creates a fresh qcow2 overlay backed by the
  # read-only Nix-store base image, and finally execs into qemu.
  runnerLauncher = i: pkgs.writeShellApplication {
    name = "gitea-actions-vm-launch-${toString i}";
    runtimeInputs = with pkgs; [
      coreutils
      unstable.gitea-actions-runner
      qemu_kvm
      util-linux
      xorriso
    ];
    text = ''
      set -eu

      work="$CACHE_DIRECTORY"
      base="${image}/image.qcow2"

      # Fresh overlay every start — recreating is cheap, and it guarantees
      # no leakage of state from the previous job. The explicit 40G virtual
      # size is what cloud-initramfs-growroot + systemd-growfs expand the
      # in-VM rootfs to on first boot; without it the overlay inherits the
      # base image's ~2 GiB, which fills up under any non-trivial job. The
      # qcow2 is sparse, so this only consumes host disk as data is written.
      rm -f "$work/overlay.qcow2"
      qemu-img create -F qcow2 -b "$base" -f qcow2 "$work/overlay.qcow2" 40G

      # Stage the cidata directory: cloud-init NoCloud reads meta-data,
      # network-config and user-data; the per-VM runner credentials travel
      # inside user-data as write_files.
      stage="$work/cidata-stage"
      rm -rf "$stage"
      mkdir -p "$stage"

      cat > "$stage/meta-data" <<EOF
      instance-id: ${config.networking.hostName}-vm-${toString i}-$(date +%s)
      local-hostname: ${config.networking.hostName}-vm-${toString i}
      EOF

      cat > "$stage/network-config" <<EOF
      version: 2
      ethernets:
        primary:
          match:
            macaddress: "${vmMac i}"
          addresses:
            - ${vmIp i}/${toString bridgePrefix}
          routes:
            - to: default
              via: ${bridgeAddress}
          nameservers:
            addresses: [1.1.1.1, 8.8.8.8]
      EOF

      (
        cd "$stage"
        gitea-runner register \
          --no-interactive --ephemeral \
          --instance "${cfg.giteaUrl}" \
          --token "$(cat "$CREDENTIALS_DIRECTORY/token")" \
          --name "${config.networking.hostName}-vm-${toString i}-$(date +%s)" \
          --labels "${lib.concatStringsSep "," cfg.labels}"

        cat > config.yaml <<EOF
      log:
        # debug (not info) so act_runner skips its NullLogger override and the
        # wrapped nektos/act job logger writes step stdout/stderr to its own
        # stdout — visible on the host journal via /dev/console. Step output
        # still ships to Gitea over the live-log API independently.
        level: debug
      runner:
        file: .runner
        capacity: 1
        fetch_timeout: 5s
        fetch_interval: 2s
        # On SIGTERM, act_runner cancels polling and waits up to this for
        # the in-flight job (if any) to finish before exiting. The in-VM
        # gitea-runner-cycle.timer fires SIGTERM hourly to recover from
        # the "unregistered runner" wedge; this needs to be >= the job
        # timeout (default 3h, matching Gitea's server-side cap) so that
        # a cycle that races a long job drains it instead of killing it.
        shutdown_timeout: 6h
      host:
        # Pin the job workspace parent away from the runner state directory
        # (/var/lib/gitea-runner) so the action can't see the .runner
        # credential at a relative path. Default would be /root/.cache/act,
        # which is already separate, but be explicit.
        workdir_parent: /var/lib/gitea-runner-jobs
      EOF
      )

      # The runner credentials ride the standard cloud-init user-data path:
      # write_files places them in /var/lib/gitea-runner before the in-VM
      # runner unit starts (it orders after cloud-final). The cloud burst
      # substrates use the identical user-data, only delivered via their
      # native metadata services instead of the NoCloud ISO.
      cat > "$stage/user-data" <<EOF
      #cloud-config
      write_files:
        - path: /var/lib/gitea-runner/.runner
          encoding: b64
          content: $(base64 -w0 "$stage/.runner")
          owner: runner:runner
          permissions: "0600"
        - path: /var/lib/gitea-runner/config.yaml
          encoding: b64
          content: $(base64 -w0 "$stage/config.yaml")
          owner: runner:runner
          permissions: "0644"
      EOF
      rm "$stage/.runner" "$stage/config.yaml"

      # ISO9660 with label cidata — recognised by cloud-init's NoCloud
      # datasource. RO from the guest's perspective by virtue of the format.
      xorriso -as mkisofs \
        -output "$work/cidata.iso" \
        -volid cidata \
        -joliet -rock \
        "$stage"

      # Hand off to QEMU. We exec so systemd tracks the qemu pid as the unit's
      # main process, and the VM's poweroff (issued by the in-VM runner unit
      # after one job) translates to a clean unit exit + restart.
      #
      # -chardev/virtio-serial/virtserialport: the qemu-guest-agent channel.
      # ExecStop and reconcile both use it to ask the guest to
      # `systemctl stop gitea-runner.service`, which lets act_runner drain
      # the current job before exiting. The in-VM unit's
      # ExecStopPost=poweroff -f then halts the VM via reboot(2), so we
      # never trigger guest systemd's poweroff.target (which would break
      # any service start that races the shutdown — e.g. apt's ubuntu-fan
      # triggers during `apt install docker`).
      exec qemu-system-x86_64 \
        -enable-kvm -cpu host \
        -smp ${toString cfg.vcpus} \
        -m ${toString cfg.memoryMiB} \
        -drive file="$work/overlay.qcow2",if=virtio,cache=writeback,discard=unmap \
        -drive file="$work/cidata.iso",if=virtio,format=raw,readonly=on \
        -netdev tap,id=net0,br=${bridgeName},helper=/run/wrappers/bin/qemu-bridge-helper \
        -device virtio-net-pci,netdev=net0,mac=${vmMac i} \
        -device virtio-balloon-pci,free-page-reporting=on \
        -device virtio-rng-pci \
        -chardev socket,path="$RUNTIME_DIRECTORY/qga.sock",server=on,wait=off,id=qga0 \
        -device virtio-serial \
        -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
        -smbios type=1,serial=ds=nocloud \
        -nographic -serial mon:stdio
    '';
  };

  # Send a shell snippet to a VM's QGA socket, run it via `sh -c`, and
  # block until it exits or the host timeout elapses. Args:
  # `<qga-sock> <timeout-seconds> <shell-snippet>`. Per qemu-ga(8) we
  # send 0xff + guest-sync at the start so a parser left mid-message
  # by a previous client (e.g. one that timed out without reading the
  # reply) doesn't poison this session. Forwards the guest's stderr.
  # Exit: 0 on guest exit 0, 1 on guest exit nonzero, 2 on host/agent
  # error or timeout.
  qgaShellScript = pkgs.writers.writePython3 "gitea-actions-vm-qga-shell" { } ''
    import base64
    import json
    import random
    import socket
    import sys
    import time


    def main():
        if len(sys.argv) != 4:
            print(
                "usage: gitea-actions-vm-qga-shell <qga-sock> "
                "<timeout-seconds> <shell-snippet>",
                file=sys.stderr,
            )
            return 2
        qga_path = sys.argv[1]
        try:
            timeout = float(sys.argv[2])
        except ValueError:
            print(f"invalid timeout: {sys.argv[2]}", file=sys.stderr)
            return 2
        snippet = sys.argv[3]

        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect(qga_path)
        except (FileNotFoundError, ConnectionRefusedError, OSError) as e:
            print(f"qga connect failed: {e}", file=sys.stderr)
            return 2

        f = s.makefile("rwb", buffering=0)

        def call(cmd):
            f.write((json.dumps(cmd) + "\n").encode())
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    return json.loads(line.decode())
                except json.JSONDecodeError:
                    continue
            return None

        sync_id = random.randint(1, 2 ** 31 - 1)
        f.write(b"\xff" + (json.dumps({
            "execute": "guest-sync",
            "arguments": {"id": sync_id},
        }) + "\n").encode())
        synced = False
        for _ in range(16):
            line = f.readline()
            if not line:
                break
            try:
                r = json.loads(line.strip().decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if r.get("return") == sync_id:
                synced = True
                break
        if not synced:
            print("qga sync failed", file=sys.stderr)
            return 2

        r = call({
            "execute": "guest-exec",
            "arguments": {
                "path": "/bin/sh",
                "arg": ["-c", snippet],
                "capture-output": True,
            },
        })
        if not r or "return" not in r:
            print(f"guest-exec failed: {r}", file=sys.stderr)
            return 2
        pid = r["return"]["pid"]

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            r = call({
                "execute": "guest-exec-status",
                "arguments": {"pid": pid},
            })
            if not r or "return" not in r:
                return 2
            if r["return"]["exited"]:
                err_b64 = r["return"].get("err-data", "")
                if err_b64:
                    try:
                        sys.stderr.write(
                            base64.b64decode(err_b64)
                            .decode(errors="replace")
                        )
                    except (ValueError, OSError):
                        pass
                code = r["return"].get("exitcode", -1)
                if code != 0:
                    print(
                        f"guest command exited with {code}",
                        file=sys.stderr,
                    )
                    return 1
                return 0
            time.sleep(0.2)

        print("guest command timed out", file=sys.stderr)
        return 2


    sys.exit(main())
  '';

  # Run inside a VM ahead of a reconcile-driven stop: drops a
  # transient systemd override on gitea-runner.service so its
  # SIGTERM→SIGKILL escalation is lifted, then daemon-reloads. After
  # this, `systemctl stop gitea-runner.service` blocks in act_runner's
  # SIGTERM handler for as long as the current job needs. The override
  # lives in /run so it disappears on the next VM boot; manual stops
  # via the host unit continue to use the unit file's TimeoutStopSec.
  prepareDrainSnippet = ''
    set -eu
    dir=/run/systemd/system/gitea-runner.service.d
    mkdir -p "$dir"
    cat > "$dir/no-stop-timeout.conf" <<'CONF'
    [Service]
    TimeoutStopSec=infinity
    CONF
    systemctl daemon-reload
  '';

  # ExecStop: ask the guest to `systemctl stop gitea-runner.service`
  # via QGA, then block until qemu (the unit's main process) exits as
  # the guest's ExecStopPost=poweroff -f reboot()s the VM. The wait
  # matters: without it, ExecStop returns in milliseconds and
  # systemd's KillMode=control-group SIGTERMs qemu, killing the VM
  # mid-drain. TimeoutStopSec=31min on the host unit caps the loop;
  # beyond that systemd aborts ExecStop and SIGKILLs qemu. The guest's
  # gitea-runner.service has its own TimeoutStopSec=30min, so worst
  # case is act_runner draining for 30 min, then poweroff -f, then
  # qemu exit.
  vmStopScript = i: pkgs.writeShellScript "gitea-actions-vm-stop-${toString i}" ''
    ${qgaShellScript} "$RUNTIME_DIRECTORY/qga.sock" 10 \
      'systemctl --no-block stop gitea-runner.service' || true
    while kill -0 "$MAINPID" 2>/dev/null; do
      sleep 2
    done
  '';

  # For each running VM, lift the in-guest stop timeout via QGA, then
  # ask the guest to systemctl-stop the runner unit. act_runner drains
  # its current job for as long as needed; when it exits, the unit's
  # ExecStopPost reboot()s the VM, qemu exits, and Restart=always on
  # the host unit launches a fresh VM with the new ExecStart.
  # Idempotent: re-running on a VM whose unit is already stopping is a
  # no-op (override write is unconditional, daemon-reload is
  # idempotent, systemctl stop on an already-stopping unit is ignored).
  reconcileScript = pkgs.writeShellScript "gitea-actions-vm-reconcile" ''
    set -u
    for i in ${lib.concatMapStringsSep " " toString instanceIds}; do
      unit="gitea-actions-vm-$i"
      qga="/run/gitea-actions-vm/$i/qga.sock"

      if ! ${pkgs.systemd}/bin/systemctl is-active --quiet "$unit"; then
        echo "$unit: not active, skipping"
        continue
      fi

      if [ ! -S "$qga" ]; then
        echo "$unit: qga socket missing, skipping"
        continue
      fi

      if ! ${qgaShellScript} "$qga" 30 ${lib.escapeShellArg prepareDrainSnippet}; then
        echo "$unit: failed to install drain override, skipping shutdown"
        continue
      fi

      echo "$unit: draining via systemctl stop gitea-runner.service (no timeout)"
      ${qgaShellScript} "$qga" 10 \
        'systemctl --no-block stop gitea-runner.service' || true
    done
  '';

  mkInstanceService = i: lib.nameValuePair "gitea-actions-vm-${toString i}" {
    description = "Gitea Actions VM runner #${toString i}";
    wantedBy = [ "multi-user.target" ];
    # Wants= (not just After=) so the bridge services are guaranteed to be in
    # the same activation transaction; without Wants= our After= is advisory.
    after = [
      "network-online.target"
      "${bridgeName}-netdev.service"
      "network-addresses-${bridgeName}.service"
    ];
    wants = [
      "network-online.target"
      "${bridgeName}-netdev.service"
      "network-addresses-${bridgeName}.service"
    ];

    # nixos-rebuild must never restart a VM directly. If a VM is running a CI
    # job we'd interrupt it; if it's idle, the reconcile unit
    # (gitea-actions-vm-reconcile, below) picks it up. Either way, when a VM
    # eventually exits naturally (ephemeral runner finishes its one job),
    # systemd auto-restarts it (Restart=always) and the new spec applies.
    restartIfChanged = false;
    stopIfChanged = false;

    serviceConfig = {
      Type = "simple";
      ExecStart = "${runnerLauncher i}/bin/gitea-actions-vm-launch-${toString i}";
      ExecStop = "${vmStopScript i}";
      Restart = "always";
      RestartSec = "5s";
      TimeoutStopSec = "31min";

      User = "gitea-actions-vm";
      Group = "gitea-actions-vm";
      SupplementaryGroups = [ "kvm" ];
      CacheDirectory = "gitea-actions-vm/${toString i}";
      CacheDirectoryMode = "0700";
      RuntimeDirectory = "gitea-actions-vm/${toString i}";
      RuntimeDirectoryMode = "0700";

      LoadCredential = "token:${config.age.secrets."gitea-actions-vm/token".path}";

      DeviceAllow = [
        "/dev/kvm rw"
        "/dev/net/tun rw"
      ];
      DevicePolicy = "closed";

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      # qemu execs qemu-bridge-helper, which carries cap_net_admin+ep — the
      # kernel only grants those caps on exec when no_new_privs is unset.
      NoNewPrivileges = false;
      RestrictSUIDSGID = false;
    };
  };
in
{
  options.custom.services.gitea.actions-vm = {
    enable = lib.mkEnableOption "VM-based Gitea Actions runners";

    instances = lib.mkOption {
      type = lib.types.ints.between 1 16;
      default = 1;
      description = "Number of concurrent VM runners on this host.";
    };

    labels = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "ubuntu-26.04-vm" "ubuntu-vm" "ubuntu-26.04" ];
      description = ''
        Labels advertised to Gitea by each runner. Note: no `:docker://...`
        suffix — jobs run directly inside the VM, not in a nested Docker
        container, since the VM itself provides isolation.
      '';
    };

    memoryMiB = lib.mkOption {
      type = lib.types.int;
      default = 12 * 1024;
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      default = 6;
    };

    giteaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://gitea.hillion.co.uk";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
      message = "custom.services.gitea.actions-vm requires x86_64-linux: the prebuilt image and qemu-system-x86_64 invocation are amd64-only.";
    }];

    users.users.gitea-actions-vm = {
      uid = config.ids.uids.gitea-actions-vm;
      group = "gitea-actions-vm";
      isSystemUser = true;
    };
    users.groups.gitea-actions-vm.gid = config.ids.gids.gitea-actions-vm;

    age.secrets."gitea-actions-vm/token" = {
      rekeyFile = ./token.age;
      mode = "0400";
    };

    # Place the per-instance overlays on /cache (wiped on boot, but on real
    # SSD-backed storage in the meantime, not the tmpfs root). The disk-heavy
    # qcow2 overlays therefore don't consume host RAM and don't fight the
    # guest's virtio-balloon page reclaim.
    custom.impermanence.cache.extraDirs = lib.mkIf
      (config.custom.impermanence.enable && config.custom.impermanence.cache.enable)
      [ "/var/cache/gitea-actions-vm" ];

    # Bridge for runner VMs. The host owns ${bridgeAddress}; each VM gets
    # a static IP injected via cloud-init's network-config on the cidata ISO.
    networking.bridges.${bridgeName}.interfaces = [ ];
    networking.interfaces.${bridgeName}.ipv4.addresses = [{
      address = bridgeAddress;
      prefixLength = bridgePrefix;
    }];

    networking.nat = {
      enable = true;
      externalInterface = "eth0";
      internalInterfaces = [ bridgeName ];
    };

    # Drop any traffic from runner VMs to private RFC1918 / CGNAT space.
    # Uses iptables extraCommands rather than nftables to coexist with the
    # host's existing iptables-based firewall (the Gitea SSH redirect rules
    # in modules/services/gitea/gitea.nix use the same mechanism, and mixing
    # nftables.enable with networking.firewall.extraCommands fails the
    # NixOS firewall assertion).
    networking.firewall.extraCommands = ''
      iptables -I FORWARD -i ${bridgeName} -d 10.0.0.0/8     -j DROP
      iptables -I FORWARD -i ${bridgeName} -d 100.64.0.0/10  -j DROP
      iptables -I FORWARD -i ${bridgeName} -d 172.16.0.0/12  -j DROP
      iptables -I FORWARD -i ${bridgeName} -d 192.168.0.0/16 -j DROP
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D FORWARD -i ${bridgeName} -d 10.0.0.0/8     -j DROP 2>/dev/null || true
      iptables -D FORWARD -i ${bridgeName} -d 100.64.0.0/10  -j DROP 2>/dev/null || true
      iptables -D FORWARD -i ${bridgeName} -d 172.16.0.0/12  -j DROP 2>/dev/null || true
      iptables -D FORWARD -i ${bridgeName} -d 192.168.0.0/16 -j DROP 2>/dev/null || true
    '';

    # SUID qemu-bridge-helper so the (DynamicUser) qemu process can attach
    # its TAP to the bridge without holding CAP_NET_ADMIN itself.
    security.wrappers."qemu-bridge-helper" = {
      source = "${pkgs.qemu_kvm}/libexec/qemu-bridge-helper";
      capabilities = "cap_net_admin+ep";
      owner = "root";
      group = "root";
    };

    environment.etc."qemu/bridge.conf".text = ''
      allow ${bridgeName}
    '';

    systemd.services = lib.listToAttrs (map mkInstanceService instanceIds) // {
      # Restart idle VMs after a config change. Pinned to each runnerLauncher
      # derivation via restartTriggers — switch-to-configuration restarts this
      # unit whenever any launcher's hash changes (vcpus, memory, image, ...),
      # which runs the reconcile script after the systemd daemon-reload, so
      # the subsequent `systemctl restart gitea-actions-vm-N` picks up the
      # new ExecStart. Busy VMs are skipped and cycle to the new spec on
      # their next ephemeral exit.
      gitea-actions-vm-reconcile = {
        description = "Reconcile Gitea Actions VMs to current config (restart idle ones)";
        wantedBy = [ "multi-user.target" ];
        after = map (i: "gitea-actions-vm-${toString i}.service") instanceIds;
        restartTriggers = map runnerLauncher instanceIds;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${reconcileScript}";
        };
      };
    };
  };
}
