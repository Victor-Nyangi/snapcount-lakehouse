"""Lambda entry point: ``lake_ingest.handler.handler``.

Event: ``{"seasons": [2025], "datasets": ["schedules", "player_week"]}``. ``datasets``
defaults to both. The bucket comes from the ``LAKE_BUCKET`` environment variable.
Returns ``{"results": [...], "ok": bool}``; ``ok`` is False only if a result ``failed``
(``source_unavailable`` is "I couldn't look", not a failure).
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable
from datetime import UTC, date, datetime
from typing import Any

from lake_ingest.fetch import fetch_dataset, http_get
from lake_ingest.sources import DATASETS
from lake_ingest.store import ObjectStore, S3Store


def run(
    event: dict,
    store: ObjectStore,
    http_get: Callable[[str], bytes],
    today: date,
) -> dict:
    seasons = [int(s) for s in event.get("seasons", [])]
    names = event.get("datasets") or list(DATASETS)
    unknown = sorted(set(names) - set(DATASETS))
    if unknown:
        raise ValueError(f"unknown dataset(s): {unknown}; known: {sorted(DATASETS)}")

    results = []
    for name in names:
        dataset = DATASETS[name]
        if dataset.per_season:
            if not seasons:
                raise ValueError(f"dataset {name!r} is per-season; the event needs 'seasons'")
            for season in seasons:
                results.append(fetch_dataset(dataset, season, http_get, store, today))
        else:
            # One file covers every season: fetch it once, however many seasons were asked for.
            results.append(fetch_dataset(dataset, None, http_get, store, today))

    as_dicts = [r.as_dict() for r in results]
    return {"results": as_dicts, "ok": all(r["status"] != "failed" for r in as_dicts)}


def _s3_store(bucket: str) -> ObjectStore:
    import boto3  # in the Lambda runtime; imported lazily so local runs don't need it

    return S3Store(bucket, boto3.client("s3"))


def handler(event: dict, context: Any) -> dict:
    store = _s3_store(os.environ["LAKE_BUCKET"])
    out = run(event, store, http_get, datetime.now(UTC).date())
    print(json.dumps(out))  # one structured line per invocation in CloudWatch
    return out
