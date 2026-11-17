from datetime import datetime, timezone

from jobs.tick import build_heartbeat


def test_build_heartbeat():
    now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
    assert build_heartbeat(now) == {"ran_at": "2026-11-17T12:00:00+00:00"}