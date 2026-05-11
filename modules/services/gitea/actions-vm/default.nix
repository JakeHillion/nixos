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
      gitea-actions-runner
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

      # Stage the cidata directory: cloud-init NoCloud reads meta-data and
      # network-config; our in-VM runner service reads .runner + config.yaml.
      # cloud-init silently ignores files it doesn't recognise.
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

      # Empty user-data — we don't run cloud-init boot scripts.
      : > "$stage/user-data"

      (
        cd "$stage"
        act_runner register \
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
      host:
        # Pin the job workspace parent away from the runner state directory
        # (/var/lib/gitea-runner) so the action can't see the .runner
        # credential at a relative path. Default would be /root/.cache/act,
        # which is already separate, but be explicit.
        workdir_parent: /var/lib/gitea-runner-jobs
      EOF
      )

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
        -smbios type=1,serial=ds=nocloud \
        -nographic -serial mon:stdio
    '';
  };

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

    serviceConfig = {
      Type = "simple";
      ExecStart = "${runnerLauncher i}/bin/gitea-actions-vm-launch-${toString i}";
      Restart = "always";
      RestartSec = "5s";

      User = "gitea-actions-vm";
      Group = "gitea-actions-vm";
      SupplementaryGroups = [ "kvm" ];
      CacheDirectory = "gitea-actions-vm/${toString i}";
      CacheDirectoryMode = "0700";

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

    systemd.services = lib.listToAttrs (map mkInstanceService instanceIds);
  };
}
