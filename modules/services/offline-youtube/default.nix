{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.offline-youtube;
  syncDir = "${config.custom.syncthing.baseDir}/media/offline-youtube";
  archive = "${syncDir}/.yt-dlp-archive.txt";
in
{
  options.custom.services.offline-youtube = {
    enable = lib.mkEnableOption "offline-youtube";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."offline-youtube/playlist.env" = {
      file = ./playlist.env.age;
      owner = "jake";
      group = "users";
    };

    systemd.services.offline-youtube-sync = {
      description = "Sync offline YouTube playlist";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];


      serviceConfig = {
        Type = "oneshot";
        User = "jake";
        Group = "users";
        WorkingDirectory = syncDir;

        # Load playlist URL from secret
        EnvironmentFile = config.age.secrets."offline-youtube/playlist.env".path;

        RuntimeDirectory = "offline-youtube";

        # Clean up videos no longer in playlist before downloading
        ExecStartPre = "${pkgs.writeShellScript "cleanup-removed-videos" ''
          set -euo pipefail

          playlist_videos="$RUNTIME_DIRECTORY/playlist-ids"

          # Get playlist video IDs. Failing here aborts the unit before
          # anything is deleted: an empty list is indistinguishable from every
          # video having been taken off the playlist.
          ${pkgs.yt-dlp}/bin/yt-dlp --flat-playlist --print id "$PLAYLIST_URL" > "$playlist_videos"
          [[ -s "$playlist_videos" ]]

          shopt -s nullglob
          for file in *; do
            [[ -f "$file" ]] || continue

            # Extract ID from filename pattern: "Title [ID].ext"
            [[ "$file" =~ \[([a-zA-Z0-9_-]{11})\]\. ]] || continue
            video_id="''${BASH_REMATCH[1]}"

            # -- : video IDs can begin with a hyphen, which grep would
            # otherwise read as options.
            if grep -qxF -- "$video_id" "$playlist_videos"; then
              continue
            fi

            rm -f -- "$file"
            echo "Deleted video: $video_id"

            # Drop the archive entry too, otherwise re-adding the video to the
            # playlist would never download it again.
            sed -i "/^youtube $video_id\$/d" ${archive}
          done
        ''}";

        ExecStart = "${pkgs.writeShellScript "sync-playlist" ''
          set -euo pipefail

          playlist_videos="$RUNTIME_DIRECTORY/playlist-ids"
          wanted="$RUNTIME_DIRECTORY/wanted"
          log="$RUNTIME_DIRECTORY/log"

          touch ${archive}
          sed 's/^/youtube /' "$playlist_videos" > "$wanted"

          considered=$(wc -l < "$playlist_videos")
          present=$(grep -cFxf "$wanted" ${archive} || true)

          ${pkgs.yt-dlp}/bin/yt-dlp \
            -f 'bestvideo+bestaudio/best' \
            --sponsorblock-mark all \
            --sponsorblock-remove sponsor \
            --download-archive ${archive} \
            -o '%(title)s [%(id)s].%(ext)s' \
            --merge-output-format mkv \
            --embed-metadata \
            --embed-chapters \
            --embed-subs \
            --retries 10 \
            --fragment-retries 10 \
            --ignore-errors \
            --no-progress \
            "$PLAYLIST_URL" 2>&1 | tee "$log" || true

          # The archive records exactly the videos that downloaded, so the
          # counts come from it rather than from parsing yt-dlp's output.
          settled=$(grep -cFxf "$wanted" ${archive} || true)

          echo "--- sync summary ---"
          echo "considered:      $considered"
          echo "already present: $present"
          echo "downloaded:      $((settled - present))"
          echo "failed:          $((considered - settled))"

          if [[ "$settled" -lt "$considered" ]]; then
            echo "failures:"
            grep '^ERROR:' "$log" | sort -u | sed 's/^/  - /'
            exit 1
          fi
        ''}";

        Restart = "on-failure";
        RestartSec = "75m";
      };
    };

    systemd.timers.offline-youtube-sync = {
      description = "Timer for offline YouTube playlist sync";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "10m";
        OnUnitInactiveSec = "6h";
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    };

    # Ensure the sync directory exists and has correct permissions
    systemd.tmpfiles.rules = [
      "d ${syncDir} 0755 jake users -"
    ];
  };
}
