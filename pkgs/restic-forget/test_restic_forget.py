"""Tests for restic_forget.py."""

import json
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, call, patch

import restic_forget


def make_snapshot(short_id, days_ago, paths=None):
    """Create a snapshot dict as restic would return."""
    t = datetime.now(timezone.utc) - timedelta(days=days_ago)
    return {
        "time": t.strftime("%Y-%m-%dT%H:%M:%S.%f+00:00"),
        "short_id": short_id,
        "id": short_id * 8,
        "paths": paths or ["/data"],
        "hostname": "test",
    }


class TestParseSnapshotTime:
    def test_basic_timestamp(self):
        t = restic_forget.parse_snapshot_time(
            "2024-01-15T10:30:00.123456+01:00"
        )
        assert t.year == 2024
        assert t.month == 1
        assert t.day == 15

    def test_nanosecond_truncation(self):
        # Restic outputs nanosecond precision; we truncate to microseconds
        t = restic_forget.parse_snapshot_time(
            "2024-01-15T10:30:00.123456789+01:00"
        )
        assert t.microsecond == 123456

    def test_utc_timezone(self):
        t = restic_forget.parse_snapshot_time("2024-06-01T00:00:00+00:00")
        assert t.tzinfo is not None


class TestGetEligibleSnapshots:
    def test_filters_young_snapshots(self):
        snapshots = [
            make_snapshot("young1", days_ago=10),
            make_snapshot("young2", days_ago=90),
        ]
        eligible = restic_forget.get_eligible_snapshots(
            snapshots, min_age_days=180
        )
        assert len(eligible) == 0

    def test_includes_old_snapshots(self):
        snapshots = [
            make_snapshot("old1", days_ago=200),
            make_snapshot("old2", days_ago=365),
        ]
        eligible = restic_forget.get_eligible_snapshots(
            snapshots, min_age_days=180
        )
        assert len(eligible) == 2

    def test_mixed_ages(self):
        snapshots = [
            make_snapshot("young", days_ago=30),
            make_snapshot("old", days_ago=200),
        ]
        eligible = restic_forget.get_eligible_snapshots(
            snapshots, min_age_days=180
        )
        assert len(eligible) == 1
        assert eligible[0]["short_id"] == "old"

    def test_sorted_oldest_first(self):
        snapshots = [
            make_snapshot("newer", days_ago=200),
            make_snapshot("oldest", days_ago=400),
            make_snapshot("middle", days_ago=300),
        ]
        eligible = restic_forget.get_eligible_snapshots(
            snapshots, min_age_days=180
        )
        assert [s["short_id"] for s in eligible] == [
            "oldest",
            "middle",
            "newer",
        ]

    def test_boundary_just_under_cutoff(self):
        # Snapshot younger than minAgeDays should not be eligible
        snapshots = [make_snapshot("boundary", days_ago=179)]
        eligible = restic_forget.get_eligible_snapshots(
            snapshots, min_age_days=180
        )
        assert len(eligible) == 0

    def test_boundary_just_over_cutoff(self):
        # Snapshot older than minAgeDays should be eligible
        snapshots = [make_snapshot("boundary", days_ago=181)]
        eligible = restic_forget.get_eligible_snapshots(
            snapshots, min_age_days=180
        )
        assert len(eligible) == 1


class TestComputeNumToForget:
    def test_under_threshold_returns_zero(self):
        result = restic_forget.compute_num_to_forget(
            total_size=1000, max_size=2000, num_snapshots=10, eligible_count=5
        )
        assert result == 0

    def test_no_snapshots_returns_zero(self):
        result = restic_forget.compute_num_to_forget(
            total_size=2000, max_size=1000, num_snapshots=0, eligible_count=0
        )
        assert result == 0

    def test_basic_estimate(self):
        # 6 TiB total, 5 TiB limit, 100 snapshots, 50 eligible
        tib = 1024**4
        result = restic_forget.compute_num_to_forget(
            total_size=6 * tib,
            max_size=5 * tib,
            num_snapshots=100,
            eligible_count=50,
        )
        # excess = 1 TiB, avg = 6 TiB / 100 = 61.4 GiB
        # ceil(1 TiB / 61.4 GiB) + 1 = ceil(16.67) + 1 = 18
        assert result == 18

    def test_caps_at_eligible_count(self):
        tib = 1024**4
        result = restic_forget.compute_num_to_forget(
            total_size=10 * tib,
            max_size=5 * tib,
            num_snapshots=10,
            eligible_count=3,
        )
        assert result == 3

    def test_small_excess(self):
        # Just barely over: should forget at least 2 (ceil(small/avg) + 1)
        result = restic_forget.compute_num_to_forget(
            total_size=1001,
            max_size=1000,
            num_snapshots=100,
            eligible_count=50,
        )
        assert result == 2  # ceil(1/10.01) + 1 = 1 + 1 = 2

    def test_single_snapshot(self):
        result = restic_forget.compute_num_to_forget(
            total_size=2000, max_size=1000, num_snapshots=1, eligible_count=1
        )
        assert result == 1


class TestTimeBased:
    @patch("restic_forget.run_restic")
    def test_forget_called_with_args(self, mock_run):
        restic_forget.time_based_forget(
            "--keep-within-daily 14d --keep-within-weekly 2m"
        )
        mock_run.assert_called_once_with(
            "forget",
            "--keep-within-daily",
            "14d",
            "--keep-within-weekly",
            "2m",
        )

    @patch("restic_forget.run_restic")
    def test_empty_args_skips(self, mock_run):
        restic_forget.time_based_forget("")
        mock_run.assert_not_called()


class TestSizeBasedForget:
    @patch("restic_forget.run_restic")
    def test_under_threshold_skips(self, mock_run):
        mock_run.return_value = json.dumps({"total_size": 1000})
        forgotten = restic_forget.size_based_forget(
            max_size=2000, min_age_days=180
        )
        assert forgotten == 0

    @patch("restic_forget.run_restic")
    def test_no_eligible_snapshots(self, mock_run):
        stats_json = json.dumps({"total_size": 3000})
        snapshots_json = json.dumps([make_snapshot("young", days_ago=10)])

        mock_run.side_effect = [stats_json, snapshots_json]
        forgotten = restic_forget.size_based_forget(
            max_size=2000, min_age_days=180
        )
        assert forgotten == 0

    @patch("restic_forget.run_restic")
    def test_forgets_oldest_first(self, mock_run):
        stats_json = json.dumps({"total_size": 3000})
        snapshots = [
            make_snapshot("old1", days_ago=400),
            make_snapshot("old2", days_ago=300),
            make_snapshot("old3", days_ago=200),
            make_snapshot("young", days_ago=10),
        ]
        snapshots_json = json.dumps(snapshots)

        # run_restic calls: stats, snapshots, then forget for each
        mock_run.side_effect = [stats_json, snapshots_json, "", "", ""]

        forgotten = restic_forget.size_based_forget(
            max_size=2000, min_age_days=180
        )
        assert forgotten > 0

        # Verify forget calls were for the oldest snapshots
        forget_calls = [
            c for c in mock_run.call_args_list if c[0][0] == "forget"
        ]
        # First forget should be the oldest snapshot
        assert forget_calls[0][0][1] == "old1"


class TestPrune:
    @patch("restic_forget.run_restic")
    def test_repack_small(self, mock_run):
        restic_forget.prune(pack_size=64, repack_small=True)
        mock_run.assert_called_once_with(
            "prune", "--repack-small", "--pack-size", "64"
        )

    @patch("restic_forget.run_restic")
    def test_max_repack_size_zero(self, mock_run):
        restic_forget.prune(pack_size=128, max_repack_size="0")
        mock_run.assert_called_once_with(
            "prune", "--max-repack-size", "0", "--pack-size", "128"
        )

    @patch("restic_forget.run_restic")
    def test_no_flags(self, mock_run):
        restic_forget.prune()
        mock_run.assert_called_once_with("prune")


class TestMain:
    @patch("restic_forget.run_restic")
    def test_time_only(self, mock_run):
        """When no --max-size, only time-based forget + prune runs."""
        mock_run.return_value = ""
        restic_forget.main(
            ["--forget-args", "--keep-within-daily 14d", "--repack-small"]
        )

        calls = mock_run.call_args_list
        # Should have: forget, prune
        assert calls[0][0][0] == "forget"
        assert calls[1][0][0] == "prune"
        assert "--repack-small" in calls[1][0]

    @patch("restic_forget.run_restic")
    def test_size_based_with_max_repack_size(self, mock_run):
        """Deep archive config: --max-repack-size 0 instead of --repack-small."""
        stats_json = json.dumps({"total_size": 1000})

        # forget args call, then stats (size check), then prune, then final stats
        mock_run.side_effect = ["", stats_json, "", stats_json]

        restic_forget.main(
            [
                "--forget-args",
                "--keep-within-daily 31d",
                "--max-size",
                "2000",
                "--max-repack-size",
                "0",
                "--pack-size",
                "128",
            ]
        )

        prune_calls = [
            c for c in mock_run.call_args_list if c[0][0] == "prune"
        ]
        assert len(prune_calls) == 1
        assert "--max-repack-size" in prune_calls[0][0]
        assert "--repack-small" not in prune_calls[0][0]
