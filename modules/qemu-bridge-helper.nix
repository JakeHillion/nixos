{ config, lib, pkgs, ... }:

let
  cfg = config.custom.qemuBridgeHelper;
in
{
  options.custom.qemuBridgeHelper = {
    allowedBridges = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Bridges unprivileged qemu processes may attach TAP devices to through qemu-bridge-helper.";
    };
  };

  config = lib.mkIf (cfg.allowedBridges != [ ]) {
    # qemu-bridge-helper with CAP_NET_ADMIN, so qemu can attach its TAP to a
    # bridge without holding the capability itself. Defined once here: the
    # wrapper's capabilities option concatenates, so a second definition
    # produces a capability string setcap rejects.
    security.wrappers."qemu-bridge-helper" = {
      source = "${pkgs.qemu_kvm}/libexec/qemu-bridge-helper";
      capabilities = "cap_net_admin+ep";
      owner = "root";
      group = "root";
    };

    environment.etc."qemu/bridge.conf".text =
      lib.concatMapStrings (bridge: "allow ${bridge}\n") cfg.allowedBridges;
  };
}
