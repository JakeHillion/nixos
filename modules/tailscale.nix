{ pkgs, lib, config, ... }:

let
  cfg = config.custom.tailscale;
in
{
  options.custom.tailscale = {
    enable = lib.mkEnableOption "tailscale";

    preAuthKeyFile = lib.mkOption {
      type = lib.types.str;
    };

    advertiseRoutes = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    advertiseExitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    ipv4Addr = lib.mkOption { type = lib.types.str; };
    ipv6Addr = lib.mkOption { type = lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.tailscale ];

    services.tailscale.enable = true;

    networking.firewall.checkReversePath = lib.mkIf cfg.advertiseExitNode "loose";

    systemd.services.tailscale-autoconnect = {
      description = "Automatic connection to Tailscale";

      # make sure tailscale is running before trying to connect to tailscale
      after = [ "network-pre.target" "tailscale.service" ];
      wants = [ "network-pre.target" "tailscale.service" ];
      wantedBy = [ "multi-user.target" ];

      # set this service as a oneshot job
      serviceConfig.Type = "oneshot";

      # have the job run this shell script
      script = with pkgs; ''
        # wait for tailscaled to settle
        sleep 2

        # check if we are already authenticated to tailscale
        status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
        if [ $status = "Running" ]; then # if so, then do nothing
          exit 0
        fi

        # otherwise authenticate with tailscale
        ${tailscale}/bin/tailscale up \
          --authkey "$(<${cfg.preAuthKeyFile})" \
          --advertise-routes "${lib.concatStringsSep "," cfg.advertiseRoutes}" \
          --advertise-exit-node=${if cfg.advertiseExitNode then "true" else "false"}
      '';
    };
  };
}
