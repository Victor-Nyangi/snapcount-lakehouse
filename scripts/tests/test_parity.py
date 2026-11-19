import gzip
from pathlib import Path

import pytest

from parity_from_snapcount import extract, main

FIXTURE = Path(__file__).parent / "fixtures" / "tiny_backfill.sql"


@pytest.fixture
def tiny_dump(tmp_path: Path) -> Path:
    # Kept as plain SQL in the repo so it can be reviewed; gzipped here like the real dump.
    dump = tmp_path / "backfill.sql.gz"
    dump.write_bytes(gzip.compress(FIXTURE.read_bytes()))
    return dump


def test_extract_counts_from_tiny_dump(tiny_dump: Path) -> None:
    expected = extract(tiny_dump, 2025)

    assert expected.season == 2025
    assert expected.rows == [
        ("games", "POST", "1"),
        ("games", "REG", "1"),
        ("player_seasons", "all", "1"),
        ("team_record", "KC", "0-1-0"),
        ("team_record", "LAC", "1-0-0"),
    ]


def test_extract_other_season(tiny_dump: Path) -> None:
    rows = extract(tiny_dump, 2024).rows

    assert ("games", "REG", "1") in rows
    assert ("games", "POST", "0") in rows
    assert ("team_record", "KC", "1-0-0") in rows


def test_extract_fails_loudly_on_a_missing_table(tmp_path: Path) -> None:
    dump = tmp_path / "broken.sql.gz"
    dump.write_bytes(gzip.compress(b"COPY public.game (id, season, game_type) FROM stdin;\n\\.\n"))

    with pytest.raises(ValueError, match="playerseasonstat"):
        extract(dump, 2025)


def test_main_writes_seed_csv(tiny_dump: Path, tmp_path: Path) -> None:
    out = tmp_path / "parity_expected_2025.csv"

    code = main(["--dump", str(tiny_dump), "--season", "2025", "--out", str(out)])

    assert code == 0
    assert out.read_text().splitlines() == [
        "metric,key,expected",
        "games,POST,1",
        "games,REG,1",
        "player_seasons,all,1",
        "team_record,KC,0-1-0",
        "team_record,LAC,1-0-0",
    ]
