"""Local CLI: ``python -m lake_ingest --season 2025 [--dataset ...] (--bucket B | --local DIR)``."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

from lake_ingest import fetch
from lake_ingest.handler import _s3_store, run
from lake_ingest.sources import DATASETS
from lake_ingest.store import LocalStore


def main(argv: list[str] | None = None, http_get: Callable[[str], bytes] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m lake_ingest", description=__doc__)
    parser.add_argument("--season", type=int, action="append", required=True)
    parser.add_argument("--dataset", action="append", choices=sorted(DATASETS))
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--bucket", help="write to this S3 bucket (uses your AWS profile)")
    target.add_argument("--local", type=Path, help="write under this local folder instead")
    args = parser.parse_args(argv)

    store = LocalStore(args.local) if args.local else _s3_store(args.bucket)
    event = {"seasons": args.season, "datasets": args.dataset}
    out = run(event, store, http_get or fetch.http_get, datetime.now(UTC).date())
    print(json.dumps(out, indent=2))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
