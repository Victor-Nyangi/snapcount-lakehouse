"""Where bronze objects go: S3 in the Lambda, a local folder for smoke runs and tests."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Protocol

MANIFEST = "_manifest.json"


class ObjectExists(Exception):
    """A write would have replaced an existing object. Bronze never changes."""


class ObjectStore(Protocol):
    def get_latest_manifest(self, prefix: str) -> dict | None: ...

    def put(self, key: str, body: bytes, content_type: str) -> None: ...


class LocalStore:
    def __init__(self, root: Path) -> None:
        self.root = Path(root)

    def get_latest_manifest(self, prefix: str) -> dict | None:
        base = self.root / prefix
        if not base.exists():
            return None
        manifests = sorted(base.rglob(MANIFEST), key=lambda p: p.relative_to(self.root).as_posix())
        return json.loads(manifests[-1].read_text()) if manifests else None

    def put(self, key: str, body: bytes, content_type: str) -> None:
        path = self.root / key
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with path.open("xb") as fh:  # "x": fail rather than overwrite
                fh.write(body)
        except FileExistsError as exc:
            raise ObjectExists(key) from exc


class S3Store:
    def __init__(self, bucket: str, client: Any) -> None:
        self.bucket = bucket
        self.client = client

    def get_latest_manifest(self, prefix: str) -> dict | None:
        latest: str | None = None
        paginator = self.client.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.endswith("/" + MANIFEST) and (latest is None or key > latest):
                    latest = key
        if latest is None:
            return None
        body = self.client.get_object(Bucket=self.bucket, Key=latest)["Body"].read()
        return json.loads(body)

    def put(self, key: str, body: bytes, content_type: str) -> None:
        # IfNoneMatch="*" is S3's conditional write: it refuses to replace an existing key,
        # so immutability is enforced by the store and not just by this code's key layout.
        try:
            self.client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=body,
                ContentType=content_type,
                IfNoneMatch="*",
            )
        except Exception as exc:
            code = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if code in {"PreconditionFailed", "ConditionalRequestConflict"}:
                raise ObjectExists(key) from exc
            raise
