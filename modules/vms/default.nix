{ config, lib, pkgs, utils, ... }:

let
  cfg = config.custom.vms;

  bridgeName = "br-vms";
  bridgeAddress = "10.108.29.1";
  bridgePrefix = 24;
  bridgeSubnet = "10.108.29.0/${toString bridgePrefix}";
  bridgeDevice = "${utils.escapeSystemdPath "/sys/subsystem/net/devices/${bridgeName}"}.device";
  # Link-local, so the VMs' IPv6 default route doesn't depend on the host's
  # global addressing.
  bridgeAddress6 = "fe80::1";

  vmIpv4 = vm: "10.108.29.${toString (10 + vm.index)}";
  vmMac = vm: "52:54:00:7e:b2:${lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString vm.index))}";

  privateRanges = [ "10.0.0.0/8" "100.64.0.0/10" "172.16.0.0/12" "192.168.0.0/16" ];

  vms = lib.attrValues cfg.instances;
  vmsWithIpv6 = lib.filter (vm: vm.ipv6Address != null) vms;

  cidata = vm:
    let
      metaData = pkgs.writeText "meta-data" ''
        instance-id: ${vm.name}
        local-hostname: ${vm.name}
      '';

      networkConfig = pkgs.writeText "network-config" (builtins.toJSON {
        version = 2;
        ethernets.primary = {
          match.macaddress = vmMac vm;
          addresses = [ "${vm.ipv4Address}/${toString bridgePrefix}" ]
            ++ lib.optional (vm.ipv6Address != null) "${vm.ipv6Address}/128";
          routes = [{ to = "0.0.0.0/0"; via = bridgeAddress; }]
            ++ lib.optional (vm.ipv6Address != null) { to = "::/0"; via = bridgeAddress6; on-link = true; };
          nameservers.addresses = [ "1.1.1.1" "8.8.8.8" ]
            ++ lib.optionals (vm.ipv6Address != null) [ "2606:4700:4700::1111" "2001:4860:4860::8888" ];
        };
      });

      userData = pkgs.writeText "user-data" ''
        #cloud-config
        ${builtins.toJSON vm.cloudConfig}
      '';
    in
    pkgs.runCommand "vm-${vm.name}-cidata.iso" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
      mkdir stage
      cp ${metaData} stage/meta-data
      cp ${networkConfig} stage/network-config
      cp ${userData} stage/user-data
      xorriso -as mkisofs -output $out -volid cidata -joliet -rock stage
    '';

  launcher = vm: pkgs.writeShellApplication {
    name = "vm-${vm.name}-launch";
    runtimeInputs = [ pkgs.coreutils pkgs.qemu_kvm pkgs.virtiofsd ];
    text = ''
      # The share directories are listed after the VM's own state directory.
      state="''${STATE_DIRECTORY%%:*}"
      disk="$state/disk.qcow2"

      # The base image is only a starting point: once the disk exists it
      # belongs to the guest and is never touched from here again.
      if [ ! -e "$disk" ]; then
        qemu-img convert -O qcow2 ${vm.baseImage} "$disk.tmp"
        qemu-img resize "$disk.tmp" ${vm.diskSize}
        mv "$disk.tmp" "$disk"
      fi

      # One virtiofsd per share. Each exits when qemu disconnects. The guest's
      # root maps to this unit's user on the host and is the only guest user
      # that can write.
      ${lib.concatMapStrings (tag: ''
        rm -f "$RUNTIME_DIRECTORY/fs-${tag}.sock"
        virtiofsd \
          --shared-dir "$state/shares/${tag}" \
          --socket-path "$RUNTIME_DIRECTORY/fs-${tag}.sock" \
          --sandbox none \
          --translate-uid map:0:${toString config.ids.uids.vms}:1 \
          --translate-gid map:0:${toString config.ids.gids.vms}:1 &
      '') vm.shares}
      ${lib.concatMapStrings (tag: ''
        for _ in $(seq 100); do [ -S "$RUNTIME_DIRECTORY/fs-${tag}.sock" ] && break; sleep 0.1; done
      '') vm.shares}

      # vhost-user-fs needs guest RAM to be shareable with virtiofsd.
      exec qemu-system-x86_64 \
        -name ${vm.name} \
        -machine q35,accel=kvm \
        -cpu host \
        -smp ${toString vm.vcpus} \
        -m ${toString vm.memoryMiB} \
        -object memory-backend-memfd,id=mem,size=${toString vm.memoryMiB}M,share=on \
        -numa node,memdev=mem \
        -drive file="$disk",if=virtio,discard=unmap \
        -drive file=${cidata vm},if=virtio,format=raw,readonly=on \
        -netdev tap,id=net0,br=${bridgeName},helper=/run/wrappers/bin/qemu-bridge-helper \
        -device virtio-net-pci,netdev=net0,mac=${vmMac vm} \
        -device virtio-balloon-pci,free-page-reporting=on \
        -device virtio-rng-pci \
        ${lib.concatMapStrings (tag:
          "-chardev socket,id=fs-${tag},path=\"$RUNTIME_DIRECTORY/fs-${tag}.sock\" -device vhost-user-fs-pci,chardev=fs-${tag},tag=${tag} ")
          vm.shares}\
        -qmp unix:"$RUNTIME_DIRECTORY/qmp.sock",server=on,wait=off \
        -chardev socket,id=qga0,path="$RUNTIME_DIRECTORY/qga.sock",server=on,wait=off \
        -device virtio-serial \
        -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
        -chardev socket,id=ser0,path="$RUNTIME_DIRECTORY/console.sock",server=on,wait=off \
        -serial chardev:ser0 \
        -display none
    '';
  };

  # ExecStop: ask the guest to shut itself down, then block until qemu exits.
  # Returning early would let systemd SIGTERM qemu, which kills the guest
  # without a shutdown. The guest agent is asked first; ACPI powerdown over
  # QMP covers a guest without a working agent. TimeoutStopSec caps the wait.
  stopScript = pkgs.writers.writePython3 "vm-stop" { } ''
    import json
    import os
    import random
    import socket
    import sys
    import time

    AGENT_GRACE = 60


    def alive(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True


    def wait_exit(pid, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not alive(pid):
                return True
            time.sleep(1)
        return not alive(pid)


    def connect(path):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(path)
        return s.makefile("rwb", buffering=0)


    def read_json(f, match):
        for _ in range(32):
            line = f.readline()
            if not line:
                return None
            try:
                r = json.loads(line.strip().decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if match(r):
                return r
        return None


    def agent_shutdown(path):
        # 0xff + guest-sync resets a parser left mid-message by an earlier
        # client. guest-shutdown sends no reply on success.
        f = connect(path)
        sync_id = random.randint(1, 2 ** 31 - 1)
        f.write(b"\xff" + json.dumps({
            "execute": "guest-sync",
            "arguments": {"id": sync_id},
        }).encode() + b"\n")
        if read_json(f, lambda r: r.get("return") == sync_id) is None:
            raise OSError("guest-sync failed")
        f.write(json.dumps({
            "execute": "guest-shutdown",
            "arguments": {"mode": "powerdown"},
        }).encode() + b"\n")


    def acpi_powerdown(path):
        f = connect(path)
        if read_json(f, lambda r: "QMP" in r) is None:
            raise OSError("no QMP greeting")
        for cmd in ("qmp_capabilities", "system_powerdown"):
            f.write(json.dumps({"execute": cmd}).encode() + b"\n")
            if read_json(f, lambda r: "return" in r or "error" in r) is None:
                raise OSError(f"{cmd} failed")


    def main():
        runtime = os.environ["RUNTIME_DIRECTORY"]
        pid = int(os.environ.get("MAINPID", "0"))
        if pid == 0 or not alive(pid):
            return 0

        try:
            agent_shutdown(os.path.join(runtime, "qga.sock"))
            print("asked guest agent to power down", file=sys.stderr)
            if wait_exit(pid, AGENT_GRACE):
                return 0
            print("guest still running, trying ACPI", file=sys.stderr)
        except OSError as e:
            print(f"guest agent unavailable: {e}", file=sys.stderr)

        try:
            acpi_powerdown(os.path.join(runtime, "qmp.sock"))
            print("sent ACPI powerdown", file=sys.stderr)
        except OSError as e:
            print(f"ACPI powerdown failed: {e}", file=sys.stderr)

        while alive(pid):
            time.sleep(1)
        return 0


    sys.exit(main())
  '';

  mkService = vm: lib.nameValuePair "vm-${vm.name}" {
    description = "VM ${vm.name}";
    # Bound to the bridge device rather than whichever unit creates it, so
    # this works with any network backend. The VM shuts down if the bridge
    # goes away, which would detach its TAP, and starts again when it returns.
    wantedBy = [ "multi-user.target" bridgeDevice ];
    bindsTo = [ bridgeDevice ];
    after = [ "network-online.target" bridgeDevice firewallUnit ];
    wants = [ "network-online.target" ];
    requires = [ firewallUnit ];

    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe (launcher vm);
      ExecStop = stopScript;
      # Includes a guest powering itself off: it comes straight back.
      Restart = "always";
      RestartSec = "5s";
      TimeoutStopSec = "5min";

      User = "vms";
      Group = "vms";
      SupplementaryGroups = [ "kvm" ];
      StateDirectory = [ "vms/${vm.name}" ]
        ++ map (tag: "vms/${vm.name}/shares/${tag}") vm.shares;
      StateDirectoryMode = "0700";
      RuntimeDirectory = "vms/${vm.name}";
      RuntimeDirectoryMode = "0700";

      DeviceAllow = [
        "/dev/kvm rw"
        "/dev/net/tun rw"
      ];
      DevicePolicy = "closed";

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      # qemu execs qemu-bridge-helper, which carries cap_net_admin+ep. The
      # kernel only grants those caps on exec when no_new_privs is unset.
      NoNewPrivileges = false;
      RestrictSUIDSGID = false;
    };
  };

  # All of the VMs' filtering and NAT lives in this one table. nftables runs
  # every table's hooks, so it applies whatever the host's own firewall is,
  # and a drop here can't be undone by an accept elsewhere.
  tableContent = ''
    chain forward {
      type filter hook forward priority filter; policy accept;
      oifname "${bridgeName}" jump to-vms
      iifname "${bridgeName}" jump from-vms
    }

    chain to-vms {
      ct state established,related accept
      # IPv4 port forwards, DNATed in prerouting.
      ct status dnat accept
      meta l4proto ipv6-icmp accept
      ${lib.concatMapStrings (vm:
        lib.concatMapStrings (port: ''
          ip6 daddr ${vm.ipv6Address} tcp dport ${toString port} accept
        '') vm.firewall.allowedTCPPorts
        + lib.concatMapStrings (port: ''
          ip6 daddr ${vm.ipv6Address} udp dport ${toString port} accept
        '') vm.firewall.allowedUDPPorts) vmsWithIpv6}
      drop
    }

    chain from-vms {
      ct state established,related accept
      ip daddr { ${lib.concatStringsSep ", " privateRanges} } drop
    }

    # The VMs need nothing from the host itself, so new connections to it
    # are dropped whatever the host's own firewall allows. ICMP covers
    # neighbour discovery for the IPv6 gateway.
    chain input {
      type filter hook input priority filter; policy accept;
      iifname "${bridgeName}" jump vms-to-host
    }

    chain vms-to-host {
      ct state established,related accept
      meta l4proto { icmp, ipv6-icmp } accept
      drop
    }

    chain prerouting {
      type nat hook prerouting priority dstnat; policy accept;
      ${lib.concatMapStrings (vm: lib.concatMapStrings (f: ''
        iifname "${cfg.externalInterface}" ${f.proto} dport ${toString f.port} dnat ip to ${vm.ipv4Address}:${toString f.port}
      '') vm.forwardPorts) vms}
      ${lib.concatMapStrings (vm:
        lib.concatMapStrings (port: ''
          ip6 daddr ${vm.ipv6Address} tcp dport ${toString port} redirect
        '') vm.hostPorts.tcp
        + lib.concatMapStrings (port: ''
          ip6 daddr ${vm.ipv6Address} udp dport ${toString port} redirect
        '') vm.hostPorts.udp) vmsWithIpv6}
    }

    chain postrouting {
      type nat hook postrouting priority srcnat; policy accept;
      ip saddr ${bridgeSubnet} oifname != "${bridgeName}" masquerade
    }
  '';

  # Declaring the table first makes the delete succeed when it doesn't
  # exist yet, so loading this file replaces the table atomically. Checked
  # at build time the same way the nftables module checks its ruleset.
  rulesFile = pkgs.writeTextFile {
    name = "vms.nft";
    text = ''
      table inet vms
      delete table inet vms
      table inet vms {
      ${tableContent}
      }
    '';
    checkPhase = ''
      export NIX_REDIRECTS=${lib.escapeShellArg (lib.concatStringsSep ":"
        (lib.mapAttrsToList (n: v: "${n}=${v}") config.networking.nftables.checkRulesetRedirects))}
      LD_PRELOAD="${pkgs.buildPackages.libredirect}/lib/libredirect.so ${pkgs.buildPackages.lklWithFirewall.lib}/lib/liblkl-hijack.so" \
        ${pkgs.buildPackages.nftables}/bin/nft --check --file $target
    '';
  };

  firewallUnit = if config.networking.nftables.enable then "nftables.service" else "vms-nftables.service";

  instanceOptions = { name, config, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        readOnly = true;
      };

      index = lib.mkOption {
        type = lib.types.ints.between 1 200;
        description = "Unique per host. Determines the VM's bridge IPv4 address and MAC.";
      };

      ipv4Address = lib.mkOption {
        type = lib.types.str;
        default = vmIpv4 config;
        readOnly = true;
        description = "The VM's address on the host bridge, reachable from the host.";
      };

      vcpus = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
      };

      memoryMiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2048;
      };

      diskSize = lib.mkOption {
        type = lib.types.str;
        default = "32G";
        description = "Size the disk is grown to when first created from the base image. Changing it later has no effect.";
      };

      baseImage = lib.mkOption {
        type = lib.types.path;
        description = "qcow2 cloud image that seeds the disk on first boot. Must run cloud-init with the NoCloud datasource.";
      };

      cloudConfig = lib.mkOption {
        type = (pkgs.formats.json { }).type;
        default = { };
        description = "cloud-config user-data. cloud-init applies it on the VM's first boot.";
      };

      ipv6Address = lib.mkOption {
        type = with lib.types; nullOr str;
        default = if cfg.ipv6Prefix == null then null else "${cfg.ipv6Prefix}${toString (10 + config.index)}";
        readOnly = true;
        description = "The VM's public IPv6 address, from custom.vms.ipv6Prefix and the index.";
      };

      firewall = {
        allowedTCPPorts = lib.mkOption {
          type = with lib.types; listOf port;
          default = [ ];
          description = "Inbound TCP ports allowed to the VM's IPv6 address.";
        };
        allowedUDPPorts = lib.mkOption {
          type = with lib.types; listOf port;
          default = [ ];
          description = "Inbound UDP ports allowed to the VM's IPv6 address.";
        };
      };

      forwardPorts = lib.mkOption {
        type = with lib.types; listOf (submodule {
          options = {
            proto = lib.mkOption { type = enum [ "tcp" "udp" ]; };
            port = lib.mkOption { type = port; };
          };
        });
        default = [ ];
        description = "Ports forwarded from the host's external IPv4 address to the VM.";
      };

      hostPorts = {
        tcp = lib.mkOption {
          type = with lib.types; listOf port;
          default = [ ];
          description = "TCP ports on the VM's IPv6 address that the host answers itself, such as a reverse proxy on the host serving the VM's names. The host's firewall must allow them.";
        };
        udp = lib.mkOption {
          type = with lib.types; listOf port;
          default = [ ];
          description = "UDP ports on the VM's IPv6 address that the host answers itself. The host's firewall must allow them.";
        };
      };

      shares = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "Host directories shared into the VM over virtiofs, stored at /var/lib/vms/<name>/shares/<tag> and mounted at /mnt/<tag> in the guest.";
      };

      sharePaths = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = lib.genAttrs config.shares (tag: "/var/lib/vms/${name}/shares/${tag}");
        readOnly = true;
        description = "Host path of each share, by tag.";
      };
    };

    config.cloudConfig.mounts = map
      (tag: [ tag "/mnt/${tag}" "virtiofs" "nofail" "0" "0" ])
      config.shares;
  };
in
{
  options.custom.vms = {
    externalInterface = lib.mkOption {
      type = lib.types.str;
      description = "Uplink interface: IPv4 NAT and port forwards go out through it.";
    };

    ipv6Prefix = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "2001:db8:1:2::";
      description = "Base of a /64 routed to this host, ending in ::. Each VM gets the prefix followed by the digits of its bridge IPv4 host number, read as hex: the VM at 10.108.29.11 gets 2001:db8:1:2::11, which is host 0x11.";
    };

    instances = lib.mkOption {
      type = with lib.types; attrsOf (submodule instanceOptions);
      default = { };
    };
  };

  config = lib.mkIf (cfg.instances != { }) {
    assertions = [{
      assertion = lib.allUnique (map (vm: vm.index) vms);
      message = "custom.vms.instances must have unique indexes.";
    }];

    users.users.vms = {
      uid = config.ids.uids.vms;
      group = "vms";
      isSystemUser = true;
    };
    users.groups.vms.gid = config.ids.gids.vms;

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/vms" ];

    networking.bridges.${bridgeName}.interfaces = [ ];
    networking.interfaces.${bridgeName} = {
      ipv4.addresses = [{ address = bridgeAddress; prefixLength = bridgePrefix; }];
      ipv6.addresses = [{ address = bridgeAddress6; prefixLength = 64; }];
      ipv6.routes = map (vm: { address = vm.ipv6Address; prefixLength = 128; }) vmsWithIpv6;
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault true;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault true;
    };

    networking.nftables.tables.vms = lib.mkIf config.networking.nftables.enable {
      family = "inet";
      content = tableContent;
    };
    # Only consulted when the host filters forwarded traffic itself. The vms
    # table still applies its own policy to this traffic.
    networking.firewall.extraForwardRules = lib.mkIf config.networking.nftables.enable ''
      iifname "${bridgeName}" accept
      oifname "${bridgeName}" accept
    '';

    systemd.services = lib.listToAttrs (map mkService vms) // lib.optionalAttrs (!config.networking.nftables.enable) {
      vms-nftables = {
        description = "nftables rules for VMs";
        wantedBy = [ "multi-user.target" ];
        # Reloading swaps the table atomically. A restart would delete it and
        # leave the VMs unfiltered in between.
        reloadIfChanged = true;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.nftables} -f ${rulesFile}";
          ExecReload = "${lib.getExe pkgs.nftables} -f ${rulesFile}";
          ExecStop = "${lib.getExe pkgs.nftables} delete table inet vms";
        };
      };
    };

    custom.qemuBridgeHelper.allowedBridges = [ bridgeName ];
  };
}
