import hashlib
import json
from datetime import date
from pathlib import Path

import pytest

from lake_ingest.fetch import SourceUnavailable, fetch_dataset
from lake_ingest.sources import DATASETS
from lake_ingest.store import LocalStore, S3Store

PARQUET = b"PAR1" + b"fake row groups" + b"PAR1"
DAY_1 = date(2026, 11, 19)
DAY_2 = date(2026, 11, 20)


def fake_http(body: bytes):
    calls: list[str] = []

    def http_get(url: str) -> bytes:
        calls.append(url)
        return body

    http_get.calls = calls  # type: ignore[attr-defined]
    return http_get


def raw_files(root: Path) -> list[Path]:
    raw = root / "raw"
    return sorted(p for p in raw.rglob("*") if p.is_file()) if raw.exists() else []


def test_fetch_writes_object_and_manifest(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)
    http_get = fake_http(PARQUET)

    result = fetch_dataset(DATASETS["player_week"], 2025, http_get, store, DAY_1)

    assert result.status == "fetched"
    assert result.key == (
        "raw/player_week/season=2025/ingest_date=2026-11-19/stats_player_week_2025.parquet"
    )
    assert result.bytes == len(PARQUET)
    assert http_get.calls == [
        "https://github.com/nflverse/nflverse-data/releases/download/"
        "stats_player/stats_player_week_2025.parquet"
    ]
    assert (tmp_path / result.key).read_bytes() == PARQUET

    manifest_path = tmp_path / "raw/player_week/season=2025/ingest_date=2026-11-19/_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    assert manifest["sha256"] == hashlib.sha256(PARQUET).hexdigest()
    assert manifest["bytes"] == len(PARQUET)
    assert manifest["status"] == "fetched"
    assert manifest["url"] == http_get.calls[0]
    assert manifest["fetched_at"]


def test_fetch_schedules_key_has_no_season(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)

    result = fetch_dataset(DATASETS["schedules"], None, fake_http(PARQUET), store, DAY_1)

    assert result.status == "fetched"
    assert result.key == "raw/schedules/ingest_date=2026-11-19/games.parquet"
    assert result.season is None


def test_fetch_unchanged_skips_write(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)
    first = fetch_dataset(DATASETS["player_week"], 2025, fake_http(PARQUET), store, DAY_1)
    before = raw_files(tmp_path)

    second = fetch_dataset(DATASETS["player_week"], 2025, fake_http(PARQUET), store, DAY_2)

    assert first.status == "fetched"
    assert second.status == "unchanged"
    assert second.key is None
    assert second.sha256 == first.sha256
    assert raw_files(tmp_path) == before
    assert not (tmp_path / "raw/player_week/season=2025/ingest_date=2026-11-20").exists()


def test_fetch_changed_body_on_later_day_writes_new_partition(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)
    fetch_dataset(DATASETS["player_week"], 2025, fake_http(PARQUET), store, DAY_1)
    newer = b"PAR1" + b"week 12 added" + b"PAR1"

    second = fetch_dataset(DATASETS["player_week"], 2025, fake_http(newer), store, DAY_2)

    assert second.status == "fetched"
    assert "ingest_date=2026-11-20" in (second.key or "")
    old = "raw/player_week/season=2025/ingest_date=2026-11-19/stats_player_week_2025.parquet"
    assert (tmp_path / old).read_bytes() == PARQUET


def test_fetch_changed_body_same_day_never_overwrites(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)
    first = fetch_dataset(DATASETS["player_week"], 2025, fake_http(PARQUET), store, DAY_1)
    newer = b"PAR1" + b"week 12 added" + b"PAR1"

    second = fetch_dataset(DATASETS["player_week"], 2025, fake_http(newer), store, DAY_1)

    assert second.status == "failed"
    assert "immutable" in (second.error or "")
    assert (tmp_path / (first.key or "")).read_bytes() == PARQUET


def test_fetch_source_unavailable_writes_no_object(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)

    def http_get(url: str) -> bytes:
        raise SourceUnavailable("HTTP 404")

    result = fetch_dataset(DATASETS["player_week"], 2025, http_get, store, DAY_1)

    assert result.status == "source_unavailable"
    assert result.key is None
    assert result.bytes == 0
    assert raw_files(tmp_path) == []
    # The run is still recorded, outside raw/, so "I couldn't look" is visible.
    runs = list((tmp_path / "runs/player_week/season=2025").glob("*.json"))
    assert len(runs) == 1
    assert json.loads(runs[0].read_text())["status"] == "source_unavailable"


def test_fetch_rejects_non_parquet(tmp_path: Path) -> None:
    store = LocalStore(tmp_path)

    result = fetch_dataset(
        DATASETS["player_week"], 2025, fake_http(b"<html>rate limited</html>"), store, DAY_1
    )

    assert result.status == "failed"
    assert result.key is None
    assert raw_files(tmp_path) == []


def test_player_week_requires_season(tmp_path: Path) -> None:
    with pytest.raises(ValueError):
        fetch_dataset(
            DATASETS["player_week"], None, fake_http(PARQUET), LocalStore(tmp_path), DAY_1
        )


class FakeS3:
    """Just enough of the boto3 S3 client for S3Store."""

    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}
        self.put_calls: list[dict] = []

    def put_object(self, **kwargs) -> dict:
        self.put_calls.append(kwargs)
        self.objects[kwargs["Key"]] = kwargs["Body"]
        return {}

    def get_paginator(self, name: str):
        assert name == "list_objects_v2"
        objects = self.objects

        class Paginator:
            def paginate(self, Bucket: str, Prefix: str):
                keys = sorted(k for k in objects if k.startswith(Prefix))
                yield {"Contents": [{"Key": k} for k in keys]} if keys else {}

        return Paginator()

    def get_object(self, Bucket: str, Key: str) -> dict:
        body = self.objects[Key]

        class Body:
            def read(self) -> bytes:
                return body

        return {"Body": Body()}


def test_s3_store_puts_with_if_none_match_and_finds_latest_manifest() -> None:
    client = FakeS3()
    store = S3Store("lake-bucket", client)

    fetch_dataset(DATASETS["player_week"], 2025, fake_http(PARQUET), store, DAY_1)
    second = fetch_dataset(DATASETS["player_week"], 2025, fake_http(PARQUET), store, DAY_2)

    assert second.status == "unchanged"
    raw_puts = [c for c in client.put_calls if c["Key"].startswith("raw/")]
    assert len(raw_puts) == 2  # the object and its manifest, once
    assert all(c["IfNoneMatch"] == "*" for c in raw_puts)
    assert all(c["Bucket"] == "lake-bucket" for c in client.put_calls)
