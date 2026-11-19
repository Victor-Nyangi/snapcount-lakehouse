"""Download one nflverse file and land it, unchanged, as a dated bronze object.

Outcomes (``IngestResult.status``):

- ``fetched``: new bytes; written to ``raw/.../ingest_date=YYYY-MM-DD/`` with a manifest.
- ``unchanged``: same sha256 as the latest manifest; nothing written under ``raw/``.
- ``source_unavailable``: 404, 5xx or a timeout. "I couldn't look", not "the run failed".
- ``failed``: the body is not Parquet, or a write would overwrite bronze, or the store broke.

Every outcome also leaves a run record under ``runs/`` (outside ``raw/``, so bronze
tables never see it).
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime

from lake_ingest.sources import Dataset
from lake_ingest.store import MANIFEST, ObjectExists, ObjectStore

HTTP_TIMEOUT_SECONDS = 60
PARQUET_MAGIC = b"PAR1"


class SourceUnavailable(Exception):
    """The source could not be read right now (404, 5xx, timeout, network)."""


@dataclass
class IngestResult:
    dataset: str
    season: int | None
    status: str  # fetched | unchanged | source_unavailable | failed
    key: str | None
    sha256: str | None
    bytes: int
    error: str | None = None

    def as_dict(self) -> dict:
        return asdict(self)


def http_get(url: str) -> bytes:
    """GET with a 60 s timeout. 404, 5xx, 429 and network errors become SourceUnavailable."""
    request = urllib.request.Request(url, headers={"User-Agent": "snapcount-lakehouse-ingest"})
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        if exc.code in (404, 429) or exc.code >= 500:
            raise SourceUnavailable(f"HTTP {exc.code} for {url}") from exc
        raise
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SourceUnavailable(f"{type(exc).__name__}: {exc} for {url}") from exc


def _season_part(dataset: Dataset, season: int | None) -> str:
    return f"season={season}/" if dataset.per_season else ""


def fetch_dataset(
    dataset: Dataset,
    season: int | None,
    http_get: Callable[[str], bytes],
    store: ObjectStore,
    today: date,
) -> IngestResult:
    if dataset.per_season and season is None:
        raise ValueError(f"dataset {dataset.name!r} is per-season; pass a season")
    if not dataset.per_season:
        season = None

    url = dataset.url(season)
    base = f"raw/{dataset.name}/{_season_part(dataset, season)}"
    folder = f"{base}ingest_date={today.isoformat()}/"
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")

    def finish(status: str, *, key=None, sha=None, size=0, error=None) -> IngestResult:
        result = IngestResult(dataset.name, season, status, key, sha, size, error)
        _record_run(store, dataset, season, url, fetched_at, result)
        return result

    try:
        body = http_get(url)
    except SourceUnavailable as exc:
        return finish("source_unavailable", error=str(exc))
    except Exception as exc:
        return finish("failed", error=f"download: {type(exc).__name__}: {exc}")

    sha = hashlib.sha256(body).hexdigest()
    if not (body.startswith(PARQUET_MAGIC) and body.endswith(PARQUET_MAGIC)):
        return finish("failed", sha=sha, size=len(body), error="body is not a Parquet file")

    try:
        latest = store.get_latest_manifest(base)
        if latest is not None and latest.get("sha256") == sha:
            return finish("unchanged", sha=sha, size=len(body))
        if latest is not None and latest.get("ingest_date") == today.isoformat():
            return finish(
                "failed",
                sha=sha,
                size=len(body),
                error=f"{folder} already holds a different file; bronze is immutable, "
                "so the change lands in tomorrow's partition",
            )

        key = folder + dataset.filename(season)
        manifest = {
            "dataset": dataset.name,
            "season": season,
            "url": url,
            "key": key,
            "sha256": sha,
            "bytes": len(body),
            "fetched_at": fetched_at,
            "ingest_date": today.isoformat(),
            "status": "fetched",
        }
        store.put(key, body, "application/vnd.apache.parquet")
        store.put(folder + MANIFEST, json.dumps(manifest, indent=2).encode(), "application/json")
    except ObjectExists as exc:
        return finish("failed", sha=sha, size=len(body), error=f"bronze is immutable: {exc}")
    except Exception as exc:
        error = f"store: {type(exc).__name__}: {exc}"
        return finish("failed", sha=sha, size=len(body), error=error)

    return finish("fetched", key=key, sha=sha, size=len(body))


def _record_run(
    store: ObjectStore,
    dataset: Dataset,
    season: int | None,
    url: str,
    fetched_at: str,
    result: IngestResult,
) -> None:
    """Best effort: a broken run log must not turn a good ingest into a failed one."""
    stamp = fetched_at.replace(":", "").replace("+0000", "Z")
    key = f"runs/{dataset.name}/{_season_part(dataset, season)}{stamp}.json"
    record = {"url": url, "fetched_at": fetched_at, **result.as_dict()}
    with contextlib.suppress(Exception):
        store.put(key, json.dumps(record, indent=2).encode(), "application/json")
