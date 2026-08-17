{ config, lib, pkgs, ... }:
let
  cfg = config.custom.services.snapcast;

  # librespot ships its own mDNS responder that binds 5353 and would collide
  # with the system avahi. Build it with avahi support so it registers through
  # the system daemon instead (the default build only supports libmdns).
  librespot = pkgs.librespot.override { withAvahi = true; };

  # Register through avahi rather than the bundled responder, and pin the port
  # the Spotify Connect handshake listens on so it can be opened on the LAN.
  librespotParams = lib.concatStringsSep "%20" [
    "--zeroconf-backend"
    "avahi"
    "--zeroconf-port"
    (toString cfg.librespotZeroconfPort)
  ];
in
{
  options.custom.services.snapcast = {
    enable = lib.mkEnableOption "snapcast snapserver";

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name advertised to Spotify Connect.";
    };

    librespotZeroconfPort = lib.mkOption {
      type = lib.types.port;
      default = 5354;
      description = "Port librespot advertises the Spotify Connect handshake on.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.snapserver = {
      enable = true;
      settings = {
        stream.source = [
          "librespot:///${lib.getExe librespot}?name=Spotify&devicename=${cfg.deviceName}&bitrate=320&params=${librespotParams}"
        ];

        # Snapclients connect here; opened per-interface by the host firewall.
        tcp-streaming.enabled = true;

        # Control/web UI is reached over Nebula via the reverse proxy below.
        http = {
          enabled = true;
          bind_to_address = "127.0.0.1";

          # Album art URLs handed to the web UI are absolute. Without a prefix
          # snapserver builds them from its own hostname and port, which no
          # client can reach; point them at the reverse proxy instead.
          url_prefix = "https://snapcast.${config.ogygia.domain}";
        };
      };
    };

    # snapserver runs DynamicUser with a StateDirectory, so its state lands in
    # /var/lib/private/snapserver (client names, per-client volumes).
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [
      "/var/lib/private/snapserver"
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."snapcast.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:1780
      '';
    };
  };
}
