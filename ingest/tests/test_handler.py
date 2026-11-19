import json
from datetime import date
from pathlib import Path

import pytest

from lake_ingest import __main__ as cli
from lake_ingest import handler as handler_mod
from lake_ingest.fetch import SourceUnavailable
from lake_ingest.store import LocalStore

PARQUET = b"PAR1" + b"rows" + b"PAR1"
TODAY = date(2026, 11, 19)


def recording_http(body: bytes = PARQUET):
    calls: list[str] = []

    def http_get(url: str) -> bytes:
        calls.append(url)
        return body

    return http_get, calls


def test_handler_runs_each_dataset_once_for_schedules(tmp_path: Path) -> None:
    http_get, calls = recording_http()
    event = {"seasons": [2024, 2025], "datasets": ["schedules", "player_week"]}

    out = handler_mod.run(event, LocalStore(tmp_path), http_get, TODAY)

    schedule_calls = [u for u in calls if u.endswith("schedules/games.parquet")]
    assert len(schedule_calls) == 1
    assert [(r["dataset"], r["season"]) for r in out["results"]] == [
        ("schedules", None),
        ("player_week", 2024),
        ("player_week", 2025),
    ]
    assert out["ok"] is True


def test_handler_defaults_to_both_datasets(tmp_path: Path) -> None:
    http_get, _ = recording_http()

    out = handler_mod.run({"seasons": [2025]}, LocalStore(tmp_path), http_get, TODAY)

    assert {r["dataset"] for r in out["results"]} == {"schedules", "player_week"}


def test_handler_rejects_unknown_dataset(tmp_path: Path) -> None:
    http_get, _ = recording_http()
    with pytest.raises(ValueError, match="unknown dataset"):
        handler_mod.run(
            {"seasons": [2025], "datasets": ["plays"]}, LocalStore(tmp_path), http_get, TODAY
        )


def test_handler_ok_false_only_on_failed(tmp_path: Path) -> None:
    def unavailable(url: str) -> bytes:
        raise SourceUnavailable("HTTP 503")

    out = handler_mod.run({"seasons": [2025]}, LocalStore(tmp_path / "a"), unavailable, TODAY)
    assert {r["status"] for r in out["results"]} == {"source_unavailable"}
    assert out["ok"] is True

    not_parquet, _ = recording_http(b"<html>")
    out = handler_mod.run({"seasons": [2025]}, LocalStore(tmp_path / "b"), not_parquet, TODAY)
    assert {r["status"] for r in out["results"]} == {"failed"}
    assert out["ok"] is False


def test_lambda_handler_reads_bucket_from_env(monkeypatch, tmp_path: Path) -> None:
    seen: dict = {}

    def fake_s3_store(bucket: str):
        seen["bucket"] = bucket
        return LocalStore(tmp_path)

    http_get, _ = recording_http()
    monkeypatch.setenv("LAKE_BUCKET", "snapcount-lake-data-test")
    monkeypatch.setattr(handler_mod, "_s3_store", fake_s3_store)
    monkeypatch.setattr(handler_mod, "http_get", http_get)

    out = handler_mod.handler({"seasons": [2025], "datasets": ["schedules"]}, None)

    assert seen["bucket"] == "snapcount-lake-data-test"
    assert out["ok"] is True
    assert out["results"][0]["status"] == "fetched"


def test_cli_local_writes_under_dir(tmp_path: Path, capsys) -> None:
    http_get, _ = recording_http()

    code = cli.main(["--season", "2025", "--local", str(tmp_path)], http_get=http_get)

    assert code == 0
    printed = json.loads(capsys.readouterr().out)
    assert [r["status"] for r in printed["results"]] == ["fetched", "fetched"]
    files = sorted(
        p.relative_to(tmp_path).as_posix() for p in (tmp_path / "raw").rglob("*.parquet")
    )
    assert len(files) == 2
    assert files[0].startswith("raw/player_week/season=2025/ingest_date=")
    assert files[1].startswith("raw/schedules/ingest_date=")


def test_cli_exit_code_nonzero_when_a_result_failed(tmp_path: Path, capsys) -> None:
    not_parquet, _ = recording_http(b"nope")

    code = cli.main(
        ["--season", "2025", "--dataset", "schedules", "--local", str(tmp_path)],
        http_get=not_parquet,
    )

    assert code == 1
