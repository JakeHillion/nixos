{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.nix-iris-push;
in
{
  options.custom.services.nix-iris-push = {
    enable = lib.mkEnableOption "Nix build signing and iris push integration";

    signingKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/data/services/nix-iris-push/signing-key";
      description = "Path to the Nix signing key file";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.custom.impermanence.enable;
      message = "nix-iris-push requires impermanence to be enabled (signing key lives under ${config.custom.impermanence.base})";
    }];

    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.signingKeyFile} 0700 root root - -"
    ];

    systemd.services.nix-iris-push-signing-key = {
      description = "Generate Nix signing key for iris push if not present";
      wantedBy = [ "multi-user.target" ];
      before = [ "nix-daemon.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "generate-nix-iris-push-signing-key" ''
          set -euo pipefail
          KEY_PATH=${lib.escapeShellArg cfg.signingKeyFile}
          if [ -f "$KEY_PATH" ]; then
            echo "Signing key already exists, skipping generation."
            exit 0
          fi
          ${pkgs.nix}/bin/nix key generate-secret --key-name "$(${pkgs.hostname}/bin/hostname)-$(${pkgs.coreutils}/bin/date +%y%m%d)" > "$KEY_PATH"
          chmod 600 "$KEY_PATH"
        '';
        RemainAfterExit = true;
      };
    };

    nix.settings.post-build-hook = pkgs.writeShellScript "nix-iris-push-post-build-hook" ''
      set -euo pipefail
      echo "[nix-iris-push] Hook fired for: $OUT_PATHS" >&2
      SIGNING_KEY=${lib.escapeShellArg cfg.signingKeyFile}
      if [ ! -f "$SIGNING_KEY" ]; then
        echo "[nix-iris-push] No signing key found, skipping push" >&2
        exit 0
      fi
      echo "$OUT_PATHS" | ${pkgs.ogygia}/bin/ogygia iris push --signing-key "$SIGNING_KEY" || {
        echo "[nix-iris-push] Push failed (non-fatal)" >&2
        exit 0
      }
    '';
  };
}
