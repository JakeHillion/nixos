{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.offline-youtube;
  syncDir = "${config.custom.syncthing.baseDir}/media/offline-youtube";
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

        # Clean up videos no longer in playlist before downloading
        ExecStartPre = "${pkgs.writeShellScript "cleanup-removed-videos" ''
          set -euo pipefail

          # Create temporary files
          current_videos=$(mktemp)
          playlist_videos=$(mktemp)
          current_sorted=$(mktemp)
          playlist_sorted=$(mktemp)

          # Extract video IDs from downloaded files
          shopt -s nullglob
          for file in *.mkv *.mp4 *.webm; do
            # Extract ID from filename pattern: "Title [ID].ext"
            if [[ "$file" =~ \[([a-zA-Z0-9_-]+)\]\. ]]; then
              echo "''${BASH_REMATCH[1]}" >> "$current_videos"
            fi
          done

          # Get playlist video IDs
          ${pkgs.yt-dlp}/bin/yt-dlp --flat-playlist --print id "$PLAYLIST_URL" > "$playlist_videos" 2>/dev/null || true

          # Find videos to delete (in current-videos but not in playlist-videos)
          if [[ -s "$current_videos" ]] && [[ -s "$playlist_videos" ]]; then
            sort -u "$current_videos" > "$current_sorted"
            sort -u "$playlist_videos" > "$playlist_sorted"

            comm -23 "$current_sorted" "$playlist_sorted" | while read -r video_id; do
              # Find and delete files matching this video ID
              find . -maxdepth 1 -type f -name "*\[$video_id\].*" -delete
              echo "Deleted video: $video_id"
            done
          fi

          # Cleanup temp files
          rm -f "$current_videos" "$playlist_videos" "$current_sorted" "$playlist_sorted"
        ''}";

        # yt-dlp command with all required options
        ExecStart = lib.strings.concatStringsSep " " [
          "${pkgs.yt-dlp}/bin/yt-dlp"

          # Format: best video + best audio
          "-f 'bestvideo+bestaudio/best'"

          # SponsorBlock: skip sponsors, create chapters for everything
          "--sponsorblock-mark all"
          "--sponsorblock-remove sponsor"

          # Download archive to track what's been downloaded
          "--download-archive '${syncDir}/.yt-dlp-archive.txt'"

          # Output template
          "-o '%(title)s [%(id)s].%(ext)s'"

          # Merge to mkv for best compatibility
          "--merge-output-format mkv"

          # Embed metadata and chapters
          "--embed-metadata"
          "--embed-chapters"
          "--embed-subs"

          # Retry on errors
          "--retries 10"
          "--fragment-retries 10"

          # Use the playlist URL from the environment variable
          "\"$PLAYLIST_URL\""
        ];

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
