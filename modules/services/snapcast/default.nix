{ config, lib, pkgs, ... }:
let
  cfg = config.custom.services.snapcast;

  shairport = pkgs.shairport-sync.override { enableAirplay2 = true; };

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
      description = "Name advertised to Spotify Connect and AirPlay.";
    };

    librespotZeroconfPort = lib.mkOption {
      type = lib.types.port;
      default = 5354;
      description = "Port librespot advertises the Spotify Connect handshake on.";
    };

    airplayPort = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Base port shairport-sync listens on for AirPlay.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.snapserver = {
      enable = true;
      settings = {
        stream.source = [
          "librespot:///${lib.getExe librespot}?name=Spotify&devicename=${cfg.deviceName}&bitrate=320&params=${librespotParams}"
          # TODO(debug): -vvv is temporary to capture shairport sync stats while
          # chasing the AirPlay audio distortion; drop it once diagnosed.
          "airplay:///${lib.getExe shairport}?name=AirPlay&devicename=${cfg.deviceName}&port=${toString cfg.airplayPort}&params=-vvv"
          # Follows whichever of the above is currently playing, so a client can
          # sit on one stream and always hear the active source. Pinned to the
          # 44.1kHz rate both real sources emit so nothing gets resampled.
          "meta:///Spotify/AirPlay?name=Meta&sampleformat=44100:16:2"
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

    # AirPlay 2 keeps time against a PTP clock provided by nqptp, which shares it
    # through /dev/shm for shairport-sync to read. It binds privileged UDP ports
    # 319/320, so it runs as root.
    systemd.services.nqptp = {
      description = "nqptp PTP clock for AirPlay 2";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = lib.getExe' pkgs.nqptp "nqptp";
        Restart = "on-failure";
      };
    };

    # snapserver spawns shairport-sync, which needs nqptp's clock available.
    systemd.services.snapserver = {
      after = [ "nqptp.service" ];
      wants = [ "nqptp.service" ];
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
