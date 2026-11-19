"""Turn snapcount's Postgres backfill dump into the lake's parity seed.

Reads the ``COPY ... FROM stdin`` blocks for ``game``, ``playerseasonstat`` and
``teamseasonstat`` (pg_dump text format) and writes ``metric,key,expected`` rows:

- ``games,REG,<n>`` and ``games,POST,<n>``
- ``player_seasons,all,<n>``
- ``team_record,<abbr>,W-L-T``

Usage::

    uv run python scripts/parity_from_snapcount.py \\
        --dump "$HOME/Bread/Projects/In Progress/snapcount/backfill.sql.gz" \\
        --season 2025 --out transform/seeds/parity_expected_2025.csv

The dump is only read, never modified.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import re
import sys
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

TABLES = ("game", "playerseasonstat", "teamseasonstat")
_COPY = re.compile(r"^COPY public\.(\w+) \((.+)\) FROM stdin;$")


@dataclass(frozen=True)
class ParityExpected:
    season: int
    rows: list[tuple[str, str, str]]

    def write_csv(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="") as fh:
            writer = csv.writer(fh, lineterminator="\n")
            writer.writerow(["metric", "key", "expected"])
            writer.writerows(self.rows)


def _copy_blocks(dump_path: Path) -> Iterator[tuple[str, list[dict[str, str | None]]]]:
    with gzip.open(dump_path, "rt", encoding="utf-8") as fh:
        table: str | None = None
        columns: list[str] = []
        rows: list[dict[str, str | None]] = []
        for raw in fh:
            line = raw.rstrip("\n")
            if table is None:
                match = _COPY.match(line)
                if match:
                    table = match.group(1)
                    columns = [c.strip().strip('"') for c in match.group(2).split(",")]
                    rows = []
                continue
            if line == "\\.":
                yield table, rows
                table = None
                continue
            values = line.split("\t")
            rows.append(
                {c: (None if v == "\\N" else v) for c, v in zip(columns, values, strict=True)}
            )


def extract(dump_path: Path, season: int) -> ParityExpected:
    tables: dict[str, list[dict[str, str | None]]] = {}
    for name, rows in _copy_blocks(Path(dump_path)):
        if name in TABLES:
            tables[name] = rows
    missing = [t for t in TABLES if t not in tables]
    if missing:
        raise ValueError(f"{dump_path} has no COPY block for: {', '.join(missing)}")

    s = str(season)
    games = [g for g in tables["game"] if g["season"] == s]
    reg = sum(1 for g in games if g["game_type"] == "REG")
    players = {p["player_id"] for p in tables["playerseasonstat"] if p["season"] == s}
    records = sorted(
        (t["team"], f"{t['wins']}-{t['losses']}-{t['ties']}")
        for t in tables["teamseasonstat"]
        if t["season"] == s
    )

    rows: list[tuple[str, str, str]] = [
        ("games", "POST", str(len(games) - reg)),
        ("games", "REG", str(reg)),
        ("player_seasons", "all", str(len(players))),
        *(("team_record", team, record) for team, record in records),
    ]
    return ParityExpected(season=season, rows=rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dump", type=Path, required=True)
    parser.add_argument("--season", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)

    expected = extract(args.dump, args.season)
    expected.write_csv(args.out)
    print(f"wrote {len(expected.rows)} rows for {args.season} to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
