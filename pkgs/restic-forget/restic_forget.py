#!/usr/bin/env python3
"""Restic forget with time-based and optional size-based retention."""

import argparse
import json
import math
import re
import shlex
import subprocess
import sys
from datetime import datetime, timedelta, timezone


def run_restic(*args):
    """Run a restic command and return stdout."""
    cmd = ["restic", *args, "--retry-lock", "30m"]
    print(f"+ {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.stdout


def get_repo_size():
    """Get total repo size in bytes via restic stats --mode raw-data."""
    output = run_restic("stats", "--mode", "raw-data", "--json")
    return json.loads(output)["total_size"]


def get_snapshots():
    """Get all snapshots, sorted oldest first."""
    output = run_restic("snapshots", "--json")
    snapshots = json.loads(output)
    return sorted(snapshots, key=lambda s: s["time"])


def parse_snapshot_time(time_str):
    """Parse a restic snapshot timestamp into a timezone-aware datetime.

    Restic outputs timestamps like '2024-01-15T10:30:00.123456789+01:00'.
    Python's fromisoformat can't handle nanosecond precision, so we truncate
    fractional seconds to microseconds.
    """
    # Truncate fractional seconds beyond 6 digits (microseconds)
    time_str = re.sub(r"(\.\d{6})\d+", r"\1", time_str)
    return datetime.fromisoformat(time_str)


def get_eligible_snapshots(snapshots, min_age_days):
    """Filter snapshots to those older than min_age_days, sorted oldest first."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=min_age_days)
    eligible = []
    for snap in snapshots:
        snap_time = parse_snapshot_time(snap["time"])
        if snap_time < cutoff:
            eligible.append(snap)
    return sorted(eligible, key=lambda s: s["time"])


def compute_num_to_forget(total_size, max_size, num_snapshots, eligible_count):
    """Estimate how many snapshots to forget to get under max_size.

    Uses average size per snapshot as a heuristic. With deduplication, each
    snapshot shares data with others, so the average overestimates the unique
    contribution of each snapshot. This means we tend to under-delete, which
    is the safe direction. The process converges over multiple runs.

    Returns the number of snapshots to forget, capped at eligible_count.
    """
    if num_snapshots == 0 or total_size <= max_size:
        return 0

    excess = total_size - max_size
    avg_per_snapshot = total_size / num_snapshots

    if avg_per_snapshot <= 0:
        return 1

    # Ceiling division + 1 safety margin
    num_to_forget = math.ceil(excess / avg_per_snapshot) + 1
    return min(num_to_forget, eligible_count)


def time_based_forget(forget_args):
    """Run restic forget with time-based retention arguments."""
    if not forget_args:
        return
    args = shlex.split(forget_args)
    run_restic("forget", *args)


def size_based_forget(max_size, min_age_days):
    """Forget oldest eligible snapshots until estimated under max_size.

    Returns the number of snapshots forgotten.
    """
    total_size = get_repo_size()
    print(f"Current repo size: {total_size} bytes", flush=True)

    if total_size <= max_size:
        print(
            f"Repo size is within limit ({total_size} <= {max_size}). "
            "No size-based cleanup needed.",
            flush=True,
        )
        return 0

    excess = total_size - max_size
    print(f"Excess: {excess} bytes over {max_size} limit", flush=True)

    snapshots = get_snapshots()
    if not snapshots:
        print("No snapshots found.", flush=True)
        return 0

    num_snapshots = len(snapshots)
    print(f"Total snapshots: {num_snapshots}", flush=True)

    eligible = get_eligible_snapshots(snapshots, min_age_days)
    eligible_count = len(eligible)
    print(
        f"Eligible snapshots (older than {min_age_days} days): {eligible_count}",
        flush=True,
    )

    if eligible_count == 0:
        print(
            f"No snapshots older than {min_age_days} days to forget. "
            "Cannot reduce size further.",
            flush=True,
        )
        return 0

    num_to_forget = compute_num_to_forget(
        total_size, max_size, num_snapshots, eligible_count
    )
    print(f"Will forget {num_to_forget} snapshots", flush=True)

    forgotten = 0
    for snap in eligible[:num_to_forget]:
        snap_id = snap["short_id"]
        snap_time = snap["time"]
        print(f"Forgetting snapshot {snap_id} from {snap_time}", flush=True)
        run_restic("forget", snap_id)
        forgotten += 1

    print(f"Forgot {forgotten} snapshots.", flush=True)
    return forgotten


def prune(pack_size=None, repack_small=False, max_repack_size=None):
    """Run restic prune with the given flags."""
    args = ["prune"]
    if repack_small:
        args.append("--repack-small")
    if max_repack_size is not None:
        args.extend(["--max-repack-size", str(max_repack_size)])
    if pack_size is not None:
        args.extend(["--pack-size", str(pack_size)])
    run_restic(*args)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Restic forget with time-based and size-based retention"
    )
    parser.add_argument(
        "--forget-args",
        type=str,
        default="",
        help="Arguments to pass to restic forget for time-based retention",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=None,
        help="Maximum repo size in bytes; oldest eligible snapshots forgotten when exceeded",
    )
    parser.add_argument(
        "--min-age-days",
        type=int,
        default=180,
        help="Minimum snapshot age in days before eligible for size-based removal",
    )
    parser.add_argument(
        "--pack-size",
        type=int,
        default=None,
        help="Pack size in MiB for restic prune",
    )
    parser.add_argument(
        "--repack-small",
        action="store_true",
        help="Repack small packs during prune",
    )
    parser.add_argument(
        "--max-repack-size",
        type=str,
        default=None,
        help="Maximum size to repack during prune (e.g., '0' for deep archive)",
    )

    args = parser.parse_args(argv)

    print("=== Restic forget ===", flush=True)

    # Step 1: Time-based forget
    if args.forget_args:
        print("--- Time-based forget ---", flush=True)
        time_based_forget(args.forget_args)

    # Step 2: Size-based forget
    if args.max_size is not None:
        print("--- Size-based forget ---", flush=True)
        size_based_forget(args.max_size, args.min_age_days)

    # Step 3: Prune
    print("--- Prune ---", flush=True)
    prune(
        pack_size=args.pack_size,
        repack_small=args.repack_small,
        max_repack_size=args.max_repack_size,
    )

    # Step 4: Report final size
    if args.max_size is not None:
        final_size = get_repo_size()
        print(f"Final repo size: {final_size} bytes", flush=True)

    print("=== Done ===", flush=True)


if __name__ == "__main__":
    main()
