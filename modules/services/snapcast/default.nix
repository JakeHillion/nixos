{ config, lib, pkgs, ... }:
let
  cfg = config.custom.services.snapcast;

  shairport = pkgs.shairport-sync.override { enableAirplay2 = true; };

  # go-librespot decodes Spotify audio to this pipe; snapserver reads it as a
  # pipe source. tmpfiles pre-creates it owned by go-librespot, and snapserver
  # uses mode=read, so the fifo isn't created (and owned) by snapserver's
  # dynamic user, which go-librespot could then not write to.
  spotifyPipe = "/run/snapcast/spotify";

  # Holds go-librespot's lockfile and session state, plus the generated config
  # it reads on startup.
  goLibrespotStateDir = "/var/lib/go-librespot";

  # Loopback-only HTTP/websocket API that the control script below reads track
  # metadata from and issues transport commands to.
  spotifyApiPort = 24879;

  goLibrespotConfig = (pkgs.formats.yaml { }).generate "go-librespot.yml" {
    device_name = cfg.deviceName;
    device_type = "speaker";
    bitrate = 320;

    audio_backend = "pipe";
    audio_output_pipe = spotifyPipe;
    audio_output_pipe_format = "s16le";

    # Register through avahi rather than the bundled responder, which would
    # bind 5353 and collide with the system daemon. Pin the port the Spotify
    # Connect handshake listens on so it can be opened on the LAN.
    zeroconf_backend = "avahi";
    zeroconf_port = cfg.spotifyZeroconfPort;

    server = {
      enabled = true;
      address = "127.0.0.1";
      port = spotifyApiPort;
    };
  };

  # snapcast ships a control script for go-librespot, but not the Python
  # environment it needs, and snapserver execs the script directly rather than
  # through an interpreter. Wrap it.
  spotifyControlScript =
    let
      python = pkgs.python3.withPackages (ps: [ ps.websocket-client ps.requests ]);
    in
    pkgs.writeShellScript "meta_go-librespot" ''
      exec ${python}/bin/python3 ${config.services.snapserver.package}/share/snapserver/plug-ins/meta_go-librespot.py "$@"
    '';

  # shairport-sync decodes AirPlay audio to this pipe; snapserver reads it as a
  # pipe source. tmpfiles pre-creates it owned by shairport, and snapserver uses
  # mode=read, so the fifo isn't created (and owned) by snapserver's dynamic
  # user, which shairport could then not write to.
  airplayPipe = "/run/snapcast/airplay";

  # shairport writes AirPlay metadata -- tags, cover art and transport state --
  # to this second pipe.
  airplayMetadataPipe = "/run/snapcast/airplay-metadata";

  # snapserver execs control scripts directly rather than through an
  # interpreter, so wrap it.
  airplayControlScript = pkgs.writeShellScript "meta_airplay" ''
    exec ${pkgs.python3}/bin/python3 ${./meta_airplay.py} --metadata-pipe=${airplayMetadataPipe} "$@"
  '';

  # LiveATC feeds are plain MP3 over HTTP, which snapcast has no native source
  # for, so ffmpeg pulls the stream and decodes it to raw PCM on stdout for a
  # process source. -reconnect* rides out brief network drops; spaces are %20
  # so the argument list survives snapserver's source-URI parsing.
  atcSource =
    let
      url = "http://d.liveatc.net/kjfk9_gnd";
      params = lib.concatStringsSep "%20" [
        "-nostdin"
        "-hide_banner"
        "-nostats"
        "-loglevel"
        "error"
        "-reconnect"
        "1"
        "-reconnect_streamed"
        "1"
        "-reconnect_delay_max"
        "5"
        "-i"
        url
        "-ac"
        "2"
        "-ar"
        "44100"
        "-f"
        "s16le"
        "-"
      ];
    in
    "process:///${lib.getExe pkgs.ffmpeg-headless}?name=KJFK-Ground&sampleformat=44100:16:2&params=${params}";
in
{
  options.custom.services.snapcast = {
    enable = lib.mkEnableOption "snapcast snapserver";

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = "Jake's Flat";
      description = "Name advertised to Spotify Connect and AirPlay.";
    };

    spotifyZeroconfPort = lib.mkOption {
      type = lib.types.port;
      default = 5354;
      description = "Port go-librespot advertises the Spotify Connect handshake on.";
    };

    airplayPort = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Port shairport-sync listens on for AirPlay.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.snapserver = {
      enable = true;
      settings = {
        stream.source = [
          "pipe://${spotifyPipe}?name=Spotify&mode=read&sampleformat=44100:16:2&controlscript=${spotifyControlScript}&controlscriptparams=--librespot-port=${toString spotifyApiPort}"
          "pipe://${airplayPipe}?name=AirPlay&mode=read&sampleformat=44100:16:2&controlscript=${airplayControlScript}"
          atcSource
          # Follows whichever of the above is currently playing, so a client can
          # sit on one stream and always hear the active source. Pinned to the
          # 44.1kHz rate both real sources emit so nothing gets resampled.
          "meta:///Spotify/AirPlay?name=Meta&sampleformat=44100:16:2"
        ];

        # Snapclients connect here; opened per-interface by the host firewall.
        tcp-streaming.enabled = true;

        # JSON-RPC control interface. hearthd drives snapcast through this, and
        # the Snapcast phone app speaks the same raw TCP protocol, so both reach
        # it over Nebula.
        tcp-control.enabled = true;

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

    # tcp-control binds to the Nebula IP, which only exists once the tunnel is
    # up; without this snapserver races nebula and fails to bind, taking the
    # audio streams down with it.
    systemd.services.snapserver = {
      after = [ "nebula-online@ogygia.service" ];
      wants = [ "nebula-online@ogygia.service" ];
    };

    # Spotify Connect receiver runs as its own service rather than being spawned
    # by snapserver, so it gets a writable directory for its lockfile and
    # session state. It decodes to a pipe that snapserver reads above.
    systemd.services.go-librespot = {
      description = "go-librespot Spotify Connect receiver";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "avahi-daemon.service" ];
      wants = [ "avahi-daemon.service" ];
      serviceConfig = {
        # StateDirectory has systemd create and chown the config directory
        # during startup, ordered after the impermanence bind-mount via
        # RequiresMountsFor, so the ownership cannot race the mount.
        StateDirectory = "go-librespot";
        StateDirectoryMode = "0700";
        # go-librespot reads its config from inside that same directory, so
        # the link is laid down once systemd has set the directory up.
        ExecStartPre = "${lib.getExe' pkgs.coreutils "ln"} -sfn ${goLibrespotConfig} ${goLibrespotStateDir}/config.yml";
        ExecStart = "${lib.getExe pkgs.unstable.go-librespot} --config_dir ${goLibrespotStateDir}";
        User = "go-librespot";
        Group = "go-librespot";
        Restart = "on-failure";
      };
    };
    users.users.go-librespot = {
      isSystemUser = true;
      group = "go-librespot";
      uid = config.ids.uids.go-librespot;
    };
    users.groups.go-librespot.gid = config.ids.gids.go-librespot;

    # AirPlay 2 receiver runs as its own service rather than being spawned by
    # snapserver, so it gets a config file and a persistent home for its pairing
    # identity. Spawned by snapserver it had neither, so the identity reset on
    # every restart and iOS refused to reconnect. It decodes to a pipe that
    # snapserver reads above.
    services.shairport-sync = {
      enable = true;
      package = shairport;
      settings = {
        general = {
          name = cfg.deviceName;
          output_backend = "pipe";
          port = cfg.airplayPort;
        };
        # Solicit metadata from the sender and hand it to the control script on
        # the stream source above.
        metadata = {
          enabled = "yes";
          include_cover_art = "yes";
          pipe_name = airplayMetadataPipe;
          # Only the dbus, MPRIS and MQTT interfaces read art back off disk,
          # and none of them are in use, so caching it would just accumulate.
          cover_art_cache_directory = "";
        };
        pipe = {
          name = airplayPipe;
          # snapserver reads this pipe as a fixed 44100:16:2 stream. shairport's
          # default "auto" output matches the *input* and can even switch format
          # mid-stream with no in-band notification, so snapserver misreads it as
          # noise. Pin the output to exactly what snapserver expects.
          output_rate = 44100;
          output_format = "S16_LE";
        };
      };
    };
    users.users.shairport.uid = config.ids.uids.shairport;
    users.groups.shairport.gid = config.ids.gids.shairport;

    # shairport-sync (AirPlay 2) needs nqptp's PTP clock available before it
    # starts.
    systemd.services.shairport-sync = {
      after = [ "nqptp.service" ];
      wants = [ "nqptp.service" ];
    };

    # Pre-create each pipe owned by the service that writes it and
    # world-readable so the snapserver dynamic user (and the control script it
    # spawns) can read it.
    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf airplayPipe} 0755 root root -"
      "p ${airplayPipe} 0644 shairport shairport -"
      "p ${airplayMetadataPipe} 0644 shairport shairport -"
      "p ${spotifyPipe} 0644 go-librespot go-librespot -"
    ];

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

    # snapserver state (DynamicUser, so /var/lib/private), shairport's AirPlay
    # pairing identity and go-librespot's session state all need to survive
    # reboots on impermanence hosts.
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [
      "/var/lib/private/snapserver"
      "/var/lib/shairport-sync"
      goLibrespotStateDir
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."snapcast.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:1780
      '';
    };
  };
}
