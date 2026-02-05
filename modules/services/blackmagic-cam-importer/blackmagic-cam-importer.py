import heapq
import os
import subprocess
import logging
from datetime import datetime
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


@dataclass
class Event:
    timestamp: datetime
    event_type: str
    file_name: Optional[str] = None
    region: Optional[str] = None

    def __lt__(self, other):
        return self.timestamp < other.timestamp


def list_mov_files() -> list[Path]:
    return [f for f in WATCH_DIR.iterdir() if f.suffix.lower() == ".mov"]


def query_immich_asset(file_name: str, api_key: str) -> Optional[dict]:
    """Query Immich for an asset by original file name."""
    headers = {"x-api-key": api_key}
    try:
        resp = requests.post(
            f"{IMMICH_URL}/api/search/metadata",
            headers=headers,
            json={"originalFileName": file_name},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        assets = data.get("assets", {}).get("items", [])
        if assets:
            if len(assets) > 1:
                log.warning(f"Found {len(assets)} Immich assets " f"for {file_name}")
            return max(
                assets,
                key=lambda a: a.get("createdAt", ""),
            )
    except Exception as e:
        log.warning(f"Failed to query Immich for {file_name}: {e}")
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
                "--property=ExecMainStartTimestamp," "ExecMainExitTimestamp,Result",
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
                    try:
                        start_time = datetime.strptime(
                            ts_str, "%a %Y-%m-%d %H:%M:%S %Z"
                        )
                    except ValueError:
                        pass
            elif line.startswith("ExecMainExitTimestamp="):
                ts_str = line.split("=", 1)[1].strip()
                if ts_str:
                    try:
                        exit_time = datetime.strptime(ts_str, "%a %Y-%m-%d %H:%M:%S %Z")
                    except ValueError:
                        pass
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
                case "ResticBackupComplete" if backup_started and not backup_complete:
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

        # Full chain found — delete the file
        file_path = WATCH_DIR / head.file_name

        def _label(e: Event) -> str:
            return e.file_name or e.region or ""

        chain_desc = " -> ".join(
            f"{e.event_type}({_label(e)}, " f"{_fmt_ts(e.timestamp)})" for e in chain
        )

        try:
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
            f"  [{i}] {_fmt_ts(ev.timestamp)} " f"{ev.event_type}{file_str}{region_str}"
        )


def main():
    log.info("Starting blackmagic-cam-importer")

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

    for mov_file in list_mov_files():
        asset = query_immich_asset(mov_file.name, api_key)
        if not asset:
            upload_to_immich(mov_file, api_key)
            asset = query_immich_asset(mov_file.name, api_key)
        if asset:
            created_str = asset.get("createdAt")
            if created_str:
                try:
                    created_at = datetime.fromisoformat(
                        created_str.replace("Z", "+00:00")
                    ).replace(tzinfo=None)
                    events.append(
                        Event(
                            timestamp=created_at,
                            event_type="ImmichFileCreated",
                            file_name=mov_file.name,
                        )
                    )
                except ValueError as e:
                    log.warning(
                        f"Failed to parse timestamp for " f"{mov_file.name}: {e}"
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

        # Process inotify events (new .mov files)
        for ie in inotify_events:
            if ie.name and ie.name.lower().endswith(".mov"):
                log.info(f"New file detected: {ie.name}")
                file_path = WATCH_DIR / ie.name
                if file_path.exists():
                    upload_to_immich(file_path, api_key)
                    asset = query_immich_asset(ie.name, api_key)
                    if not asset:
                        log.warning(
                            f"Asset not found in Immich after " f"upload: {ie.name}"
                        )
                    else:
                        created_str = asset.get("createdAt")
                        if created_str:
                            try:
                                created_at = datetime.fromisoformat(
                                    created_str.replace("Z", "+00:00")
                                ).replace(tzinfo=None)
                                new_events.append(
                                    Event(
                                        timestamp=created_at,
                                        event_type="ImmichFileCreated",
                                        file_name=ie.name,
                                    )
                                )
                            except ValueError as e:
                                log.warning(
                                    f"Failed to parse timestamp " f"for {ie.name}: {e}"
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
                log.info(f"Service {svc} completed " f"successfully at {exit_time}")
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
