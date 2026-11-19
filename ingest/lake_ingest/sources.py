"""The nflverse release files this lake reads, and where they live."""

from __future__ import annotations

from dataclasses import dataclass

BASE_URL = "https://github.com/nflverse/nflverse-data/releases/download/"


@dataclass(frozen=True)
class Dataset:
    name: str
    url_template: str
    per_season: bool

    def url(self, season: int | None) -> str:
        return self.url_template.format(season=season)

    def filename(self, season: int | None) -> str:
        return self.url(season).rsplit("/", 1)[-1]


DATASETS: dict[str, Dataset] = {
    # One file for every season since 1999; filtered to the lake's window in dbt.
    "schedules": Dataset(
        name="schedules",
        url_template=BASE_URL + "schedules/games.parquet",
        per_season=False,
    ),
    "player_week": Dataset(
        name="player_week",
        url_template=BASE_URL + "stats_player/stats_player_week_{season}.parquet",
        per_season=True,
    ),
}
