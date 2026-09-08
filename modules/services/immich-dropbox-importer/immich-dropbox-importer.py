import hashlib
import heapq
import os
import subprocess
import logging
from datetime import datetime, timezone
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import requests
from inotify_simple import INotify, flags

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
log = logging.getLogger(__name__)

WATCH_DIR = Path(os.environ["WATCH_DIR"])
IMMICH_URL = os.environ["IMMICH_URL"]
IMMICH_API_KEY_FILE = Path(os.environ["IMMICH_API_KEY_FILE"])

CLONE_REGIONS = ["aws-us-east-1", "aws-eu-central-2"]
RESTIC_SERVICES = ["restic-backups-immich"] + [
    f"restic-clone-b52-{r}" for r in CLONE_REGIONS
]
POLL_INTERVAL = 600  # seconds

SERVICE_EVENT_TYPES: dict[str, tuple[str, str, Optional[str]]] = {
    "restic-backups-immich": (
        "ResticBackupStarted",
        "ResticBackupComplete",
        None,
    ),
}
for _region in CLONE_REGIONS:
    SERVICE_EVENT_TYPES[f"restic-clone-b52-{_region}"] = (
        "ResticCloneStarted",
        "ResticCloneComplete",
        _region,
    )


def get_api_key() -> str:
    return IMMICH_API_KEY_FILE.read_text().strip()


def _parse_immich_timestamp(created_str: str) -> Optional[datetime]:
    """Parse an Immich `createdAt` (ISO 8601, UTC) as UTC-aware."""
    try:
        return datetime.fromisoformat(created_str.replace("Z", "+00:00"))
    except ValueError:
        return None


def _parse_systemd_timestamp(ts_str: str) -> Optional[datetime]:
    """Parse a `systemctl show` timestamp (naive local time) to UTC-aware.

    systemctl reports `ExecMain*Timestamp` in the host's local timezone, but
    strptime's *%Z* leaves the datetime naive. Use datetime.timestamp(), which
    interprets a naive datetime as the local wall-clock, then re-express as
    UTC. This correctly accounts for DST (e.g. Europe/London BST) so all events
    share one UTC basis.
    """
    if not ts_str:
        return None
    try:
        naive_local = datetime.strptime(ts_str, "%a %Y-%m-%d %H:%M:%S %Z")
    except ValueError:
        return None
    try:
        return datetime.fromtimestamp(naive_local.timestamp(), tz=timezone.utc)
    except (ValueError, OverflowError, OSError):
        return None


@dataclass
class Event:
    timestamp: datetime
    event_type: str
    file_name: Optional[str] = None
    checksum: Optional[str] = None
    region: Optional[str] = None

    def __lt__(self, other):
        if self.timestamp.tzinfo is None or other.timestamp.tzinfo is None:
            raise ValueError("Event timestamps must be timezone-aware (UTC)")
        return self.timestamp < other.timestamp


MEDIA_SUFFIXES = {
    ".mov",
    ".jpg",
    ".jpeg",
}


def is_media_file(name: str) -> bool:
    return Path(name).suffix.lower() in MEDIA_SUFFIXES


def list_media_files() -> list[Path]:
    return [f for f in WATCH_DIR.iterdir() if is_media_file(f.name)]


def file_sha1(file_path: Path) -> str:
    """Compute the SHA1 hex checksum of a file, matching Immich's checksum."""
    h = hashlib.sha1()
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def check_immich_assets(
    checksums: dict[str, str], api_key: str
) -> dict[str, Optional[str]]:
    """Map each {filename: checksum} to its existing Immich asset id.

    A single bulk-upload-check request covers all checksums at once; it matches
    purely by content checksum (not filename), so it is robust to filename
    collisions between sources. A file with no matching asset maps to None.
    """
    result_map: dict[str, Optional[str]] = {name: None for name in checksums}
    headers = {"x-api-key": api_key}
    try:
        resp = requests.post(
            f"{IMMICH_URL}/api/assets/bulk-upload-check",
            headers=headers,
            json={
                "assets": [
                    {"id": name, "checksum": checksum}
                    for name, checksum in checksums.items()
                ]
            },
            timeout=60,
        )
        resp.raise_for_status()
        for result in resp.json().get("results", []):
            name = result.get("id")
            action = result.get("action")
            if name not in result_map:
                continue
            if action == "reject":
                asset_id = result.get("assetId")
                if not asset_id:
                    log.warning(
                        f"Immich reports duplicate but no assetId for "
                        f"{name}"
                    )
                result_map[name] = asset_id
            elif action != "accept":
                log.warning(
                    f"Unexpected bulk-upload-check action for {name}: "
                    f"{result}"
                )
    except Exception as e:
        log.warning(f"Failed to query Immich for checksums: {e}")
    return result_map


def fetch_created_at(asset_id: str, api_key: str) -> Optional[datetime]:
    """Fetch an asset by id from Immich and return its createdAt."""
    headers = {"x-api-key": api_key}
    try:
        resp = requests.get(
            f"{IMMICH_URL}/api/assets/{asset_id}",
            headers=headers,
            timeout=30,
        )
        resp.raise_for_status()
        created_str = resp.json().get("createdAt")
        if created_str:
            return _parse_immich_timestamp(created_str)
    except Exception as e:
        log.warning(f"Failed to fetch asset {asset_id}: {e}")
    return None


def upload_to_immich(file_path: Path, api_key: str) -> bool:
    """Upload a file to Immich using immich-cli."""
    try:
        result = subprocess.run(
            [
                "immich",
                "upload",
                "-u",
                IMMICH_URL,
                "-k",
                api_key,
                str(file_path),
            ],
            capture_output=True,
            text=True,
            timeout=600,
        )
        if result.returncode == 0:
            log.info(f"Uploaded {file_path.name} to Immich")
            return True
        else:
            log.error(f"Failed to upload {file_path.name}: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        log.error(f"Timeout uploading {file_path.name}")
        return False
    except Exception as e:
        log.error(f"Error uploading {file_path.name}: {e}")
        return False


def get_service_timestamps(
    service_name: str,
) -> tuple[Optional[datetime], Optional[datetime], bool]:
    """Get start time, exit time, and success status from systemd."""
    try:
        result = subprocess.run(
            [
                "systemctl",
                "show",
                f"{service_name}.service",
                "--property=ExecMainStartTimestamp,"
                "ExecMainExitTimestamp,Result",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return None, None, False

        start_time = None
        exit_time = None
        success = False

        for line in result.stdout.strip().split("\n"):
            if line.startswith("ExecMainStartTimestamp="):
                ts_str = line.split("=", 1)[1].strip()
                if ts_str:
                    start_time = _parse_systemd_timestamp(ts_str)
            elif line.startswith("ExecMainExitTimestamp="):
                ts_str = line.split("=", 1)[1].strip()
                if ts_str:
                    exit_time = _parse_systemd_timestamp(ts_str)
            elif line.startswith("Result="):
                success = line.split("=", 1)[1].strip() == "success"

        return start_time, exit_time, success
    except Exception as e:
        log.warning(f"Failed to get timestamps for {service_name}: {e}")
        return None, None, False


def try_cleanup(events: list[Event]) -> None:
    """Process events from the head, deleting files with complete chains."""
    while events:
        head = events[0]

        if head.event_type != "ImmichFileCreated":
            events.pop(0)
            continue

        # Single forward scan for the full chain. Events are
        # sorted so ordering is implicit — no timestamp checks.
        chain: list[Event] = [head]
        backup_started = False
        backup_complete = False
        clone_started: set[str] = set()
        clone_complete: set[str] = set()
        for ev in events[1:]:
            match ev.event_type:
                case "ResticBackupStarted" if not backup_started:
                    backup_started = True
                    chain.append(ev)
                case "ResticBackupComplete" if (
                    backup_started and not backup_complete
                ):
                    backup_complete = True
                    chain.append(ev)
                case "ResticCloneStarted" if (
                    backup_complete and ev.region not in clone_started
                ):
                    clone_started.add(ev.region)
                    chain.append(ev)
                case "ResticCloneComplete" if (
                    backup_complete
                    and ev.region in clone_started
                    and ev.region not in clone_complete
                ):
                    clone_complete.add(ev.region)
                    chain.append(ev)

        if not backup_complete:
            break
        if clone_complete != set(CLONE_REGIONS):
            break

        # Full chain found — delete the file. Verify the on-disk content
        # still matches the recorded checksum before deleting, so a
        # same-named file from a different source is never removed.
        file_path = WATCH_DIR / head.file_name

        def _label(e: Event) -> str:
            return e.file_name or e.region or ""

        chain_desc = " -> ".join(
            f"{e.event_type}({_label(e)}, " f"{_fmt_ts(e.timestamp)})"
            for e in chain
        )

        try:
            if head.checksum is not None:
                disk_checksum = file_sha1(file_path)
                if disk_checksum != head.checksum:
                    log.error(
                        f"Refusing to delete {head.file_name}: on-disk "
                        f"content changed since import "
                        f"(checksum {disk_checksum}, expected "
                        f"{head.checksum}). Leaving file for manual review."
                    )
                    events.pop(0)
                    continue
            file_path.unlink()
            log.info(f"Deleted {head.file_name}: {chain_desc}")
        except FileNotFoundError:
            log.info(f"Already gone {head.file_name}: " f"{chain_desc}")
        except OSError as e:
            log.error(f"Failed to delete {head.file_name}: {e}")
            break

        # Only remove the file event; service events are shared
        events.pop(0)


def _fmt_ts(ts: datetime) -> str:
    return ts.strftime("%Y-%m-%d %H:%M:%S.%f")


def log_queue(events: list[Event]) -> None:
    """Log every event in the queue."""
    log.info(f"Event queue ({len(events)} events):")
    for i, ev in enumerate(events):
        region_str = f", region={ev.region}" if ev.region else ""
        file_str = f", file={ev.file_name}" if ev.file_name else ""
        log.info(
            f"  [{i}] {_fmt_ts(ev.timestamp)} "
            f"{ev.event_type}{file_str}{region_str}"
        )


def main():
    log.info("Starting immich-dropbox-importer")

    api_key = get_api_key()

    # Setup inotify
    inotify = INotify()
    watch_flags = flags.MOVED_TO | flags.CLOSE_WRITE
    inotify.add_watch(WATCH_DIR, watch_flags)
    log.info(f"Watching {WATCH_DIR}")

    # Phase 1: gather events unsorted
    events: list[Event] = []
    last_seen_start: dict[str, Optional[datetime]] = {}
    last_seen_exit: dict[str, Optional[datetime]] = {}

    files = list_media_files()
    checksums = {mov_file.name: file_sha1(mov_file) for mov_file in files}

    # Single bulk-upload-check covering the whole inbox.
    first_check = check_immich_assets(checksums, api_key)
    for name, asset_id in first_check.items():
        if asset_id is None:
            log.info(
                f"New content {name} (checksum {checksums[name]}), "
                f"uploading to Immich"
            )
            upload_to_immich(WATCH_DIR / name, api_key)
        else:
            log.info(
                f"Already in Immich as asset {asset_id} for {name} "
                f"(checksum {checksums[name]}); tracking for deletion "
                f"against the next restic chain, no upload"
            )

    # Re-check so freshly-uploaded files get their asset ids.
    results = check_immich_assets(checksums, api_key)
    for name, asset_id in results.items():
        if not asset_id:
            log.warning(f"Asset not found in Immich after upload: {name}")
            continue
        created_at = fetch_created_at(asset_id, api_key)
        if created_at:
            events.append(
                Event(
                    timestamp=created_at,
                    event_type="ImmichFileCreated",
                    file_name=name,
                    checksum=checksums[name],
                )
            )
        else:
            log.warning(
                f"Failed to read createdAt for {name} (asset {asset_id})"
            )

    for svc in RESTIC_SERVICES:
        start_time, exit_time, success = get_service_timestamps(svc)
        last_seen_start[svc] = start_time
        last_seen_exit[svc] = exit_time
        start_type, complete_type, region = SERVICE_EVENT_TYPES[svc]
        if start_time:
            events.append(
                Event(
                    timestamp=start_time,
                    event_type=start_type,
                    region=region,
                )
            )
        if exit_time and success:
            events.append(
                Event(
                    timestamp=exit_time,
                    event_type=complete_type,
                    region=region,
                )
            )

    events.sort()
    log_queue(events)
    try_cleanup(events)

    # Phase 2: event loop
    log.info("Entering event loop")
    while True:
        inotify_events = inotify.read(timeout=POLL_INTERVAL * 1000)
        new_events: list[Event] = []

        # Process inotify events (new media files) in one batch.
        candidate_paths: dict[str, Path] = {}
        pending_checksums = {ev.checksum for ev in events + new_events}
        candidates: dict[str, str] = {}  # filename -> checksum
        for ie in inotify_events:
            if not (ie.name and is_media_file(ie.name)):
                continue
            log.info(f"New file detected: {ie.name}")
            file_path = WATCH_DIR / ie.name
            if not file_path.exists():
                continue

            checksum = file_sha1(file_path)

            # Dedupe by checksum across pending events so the same
            # content (e.g. CLOSE_WRITE then MOVED_TO, or identical
            # bytes under two names) is only imported once.
            if checksum in pending_checksums:
                log.info(
                    f"Skipping {ie.name}: content already imported "
                    f"(checksum {checksum})"
                )
                continue

            candidate_paths[ie.name] = file_path
            candidates[ie.name] = checksum

        if candidates:
            # Single bulk-upload-check for the whole batch.
            first_check = check_immich_assets(candidates, api_key)
            for name, asset_id in first_check.items():
                if asset_id is None:
                    log.info(
                        f"New content {name} (checksum {candidates[name]}), "
                        f"uploading to Immich"
                    )
                    upload_to_immich(candidate_paths[name], api_key)
                else:
                    log.info(
                        f"Already in Immich as asset {asset_id} for "
                        f"{name} (checksum {candidates[name]}); tracking "
                        f"for deletion against the next restic chain, "
                        f"no upload"
                    )

            # Re-check so freshly-uploaded files get their asset ids.
            results = check_immich_assets(candidates, api_key)
            for name, asset_id in results.items():
                if not asset_id:
                    log.warning(
                        f"Asset not found in Immich after upload: {name}"
                    )
                    continue
                created_at = fetch_created_at(asset_id, api_key)
                if created_at:
                    new_events.append(
                        Event(
                            timestamp=created_at,
                            event_type="ImmichFileCreated",
                            file_name=name,
                            checksum=candidates[name],
                        )
                    )
                else:
                    log.warning(
                        f"Failed to read createdAt for {name} "
                        f"(asset {asset_id}). It has been uploaded but "
                        f"will not be tracked for deletion."
                    )

        # Poll systemd for restic service changes
        for svc in RESTIC_SERVICES:
            start_time, exit_time, success = get_service_timestamps(svc)
            start_type, complete_type, region = SERVICE_EVENT_TYPES[svc]

            prev_start = last_seen_start.get(svc)
            if start_time is not None and (
                prev_start is None or start_time > prev_start
            ):
                log.info(f"Service {svc} started at {start_time}")
                new_events.append(
                    Event(
                        timestamp=start_time,
                        event_type=start_type,
                        region=region,
                    )
                )
            last_seen_start[svc] = start_time

            prev_exit = last_seen_exit.get(svc)
            if (
                exit_time is not None
                and success
                and (prev_exit is None or exit_time > prev_exit)
            ):
                log.info(
                    f"Service {svc} completed " f"successfully at {exit_time}"
                )
                new_events.append(
                    Event(
                        timestamp=exit_time,
                        event_type=complete_type,
                        region=region,
                    )
                )
            last_seen_exit[svc] = exit_time

        if new_events:
            new_events.sort()
            events = list(heapq.merge(events, new_events))
            log_queue(events)
            try_cleanup(events)


if __name__ == "__main__":
    main()
