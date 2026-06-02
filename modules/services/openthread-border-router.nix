{ config, lib, pkgs, nixpkgs-unstable, ... }:

let
  cfg = config.custom.services.openthread-border-router;
in
{
  imports = [ "${nixpkgs-unstable}/nixos/modules/services/home-automation/openthread-border-router.nix" ];
  disabledModules = [ "services/home-automation/openthread-border-router.nix" ];

  options.custom.services.openthread-border-router = {
    enable = lib.mkEnableOption "openthread-border-router";

    radioHost = lib.mkOption {
      type = lib.types.str;
      default = "slzb-06mu.iot.home.jakehillion.me";
      description = "Host of the network-attached Thread RCP.";
    };

    radioPort = lib.mkOption {
      type = lib.types.port;
      default = 6638;
      description = "TCP port of the network-attached Thread RCP.";
    };

    backboneInterface = lib.mkOption {
      type = lib.types.str;
      default = "iot";
      description = "Backbone interface for Thread border routing (mDNS/SRP, TREL).";
    };
  };

  config = lib.mkIf cfg.enable {
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/thread" ];

    systemd.services.otbr-socat = {
      description = "socat TCP <-> pty bridge for OTBR Thread RCP";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat -d pty,raw,echo=0,link=/run/otbr/ttyOTBR,ignoreeof tcp:${cfg.radioHost}:${toString cfg.radioPort}";
        RuntimeDirectory = "otbr";
        RuntimeDirectoryPreserve = "yes";
        Restart = "always";
        RestartSec = 5;
      };
    };

    systemd.services.otbr-agent = {
      requires = [ "otbr-socat.service" ];
      after = [ "otbr-socat.service" ];
    };

    services.openthread-border-router = {
      enable = true;
      # OpenThread picks an ephemeral UDP port for the primary MeshCoP
      # BorderAgent unless OPENTHREAD_CONFIG_BORDER_AGENT_UDP_PORT is set at
      # compile time. Pin to 49191 so the firewall rule can be a single port.
      package = pkgs.unstable.openthread-border-router.overrideAttrs (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE =
            (old.env.NIX_CFLAGS_COMPILE or "")
              + " -DOPENTHREAD_CONFIG_BORDER_AGENT_UDP_PORT=49191";
        };
      });
      backboneInterfaces = [ cfg.backboneInterface ];
      radio.url = "spinel+hdlc+uart:///run/otbr/ttyOTBR?uart-baudrate=460800&uart-init-deassert";
      radio.extraDevices = [ "trel://${cfg.backboneInterface}" ];
    };
  };
}
