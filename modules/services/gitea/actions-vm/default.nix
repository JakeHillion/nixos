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
      e2fsprogs
      gitea-actions-runner
      iproute2
      qemu_kvm
      util-linux
      yq-go
    ];
    text = ''
      set -eu

      work="$STATE_DIRECTORY"
      base="${image}/image.qcow2"

      # Fresh overlay every start — recreating is cheap, and it guarantees
      # no leakage of state from the previous job.
      rm -f "$work/overlay.qcow2"
      qemu-img create -F qcow2 -b "$base" -f qcow2 "$work/overlay.qcow2" 40G

      # Stage the runner-state directory: act_runner register --ephemeral
      # writes a .runner JSON containing the per-instance secret. We pair it
      # with a config.yaml telling act_runner which protocol to speak.
      stage="$work/state-stage"
      rm -rf "$stage"
      mkdir -p "$stage"
      (
        cd "$stage"
        act_runner register \
          --no-interactive --ephemeral \
          --instance "${cfg.giteaUrl}" \
          --token "$(cat "$CREDENTIALS_DIRECTORY/token")" \
          --name "${config.networking.hostName}-vm-${toString i}-$(date +%s)" \
          --labels "${lib.concatStringsSep "," cfg.labels}"

        # Minimal runner config; defaults are fine otherwise.
        cat > config.yaml <<EOF
      log:
        level: info
      runner:
        file: .runner
        capacity: 1
        fetch_timeout: 5s
        fetch_interval: 2s
      EOF
      )

      # Build the read-only RUNNERSTATE ext4 image the guest will mount.
      truncate -s 16M "$work/state.img"
      mkfs.ext4 -L RUNNERSTATE -d "$stage" "$work/state.img"

      # Hand off to QEMU. We exec so systemd tracks the qemu pid as the unit's
      # main process, and the VM's poweroff (issued by the in-VM runner unit
      # after one job) translates to a clean unit exit + restart.
      exec qemu-system-x86_64 \
        -enable-kvm -cpu host \
        -smp ${toString cfg.vcpus} \
        -m ${toString cfg.memoryMiB} \
        -drive file="$work/overlay.qcow2",if=virtio,cache=writeback,discard=unmap \
        -drive file="$work/state.img",if=virtio,format=raw,readonly=on \
        -netdev tap,id=net0,br=${bridgeName},helper=/run/wrappers/bin/qemu-bridge-helper \
        -device virtio-net-pci,netdev=net0,mac=${vmMac i} \
        -device virtio-balloon-pci,free-page-reporting=on \
        -device virtio-rng-pci \
        -nographic -serial mon:stdio
    '';
  };

  mkInstanceService = i: lib.nameValuePair "gitea-actions-vm-${toString i}" {
    description = "Gitea Actions VM runner #${toString i}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "${bridgeName}-netdev.service" ]
      ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];
    wants = [ "network-online.target" ]
      ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${runnerLauncher i}/bin/gitea-actions-vm-launch-${toString i}";
      Restart = "always";
      RestartSec = "5s";

      DynamicUser = true;
      SupplementaryGroups = [ "kvm" ];
      StateDirectory = "gitea-actions-vm/${toString i}";
      StateDirectoryMode = "0700";

      LoadCredential = "token:${config.age.secrets."gitea-actions-vm/token".path}";

      DeviceAllow = [
        "/dev/kvm rw"
        "/dev/net/tun rw"
      ];
      DevicePolicy = "closed";

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictSUIDSGID = false; # qemu-bridge-helper is SUID and must be exec'd
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
      default = [ "ubuntu-26.04-vm" "ubuntu-vm" ];
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
      [ "/var/lib/private/gitea-actions-vm" ];

    # Bridge for runner VMs. Host owns ${bridgeAddress}; VMs DHCP via... no
    # DHCP is run — VMs use cloud-image's default DHCP client which would
    # have nothing to talk to. To keep the host module simple we ship a tiny
    # stateless DHCP server (dnsmasq) bound to the bridge.
    networking.bridges.${bridgeName}.interfaces = [ ];
    networking.interfaces.${bridgeName}.ipv4.addresses = [{
      address = bridgeAddress;
      prefixLength = bridgePrefix;
    }];

    services.dnsmasq = {
      enable = true;
      settings = {
        interface = bridgeName;
        bind-interfaces = true;
        # Don't try to resolve recursively; just hand out leases on br-runners.
        port = 0;
        dhcp-range = "10.108.28.10,10.108.28.250,12h";
        dhcp-option = [
          "3,${bridgeAddress}" # default route
          "6,1.1.1.1,8.8.8.8" # DNS — public only (do not leak internal DNS to runner VMs)
        ];
      };
    };

    networking.firewall.interfaces.${bridgeName} = {
      allowedUDPPorts = [ 67 ]; # DHCP
    };

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
