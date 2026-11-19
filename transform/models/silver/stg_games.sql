-- One row per game from the newest schedules ingest. Bronze keeps every ingest as its own
-- ingest_date partition; reading only the newest means a re-ingest never double-counts.

with latest_ingest as (
    select max(ingest_date) as ingest_date
    from {{ source('bronze', 'schedules') }}
),

schedules as (
    select
        s.game_id,
        s.season,
        s.week,
        s.game_type,
        s.gameday,
        s.home_team,
        s.away_team,
        s.home_score,
        s.away_score,
        s.overtime
    from {{ source('bronze', 'schedules') }} as s
    inner join latest_ingest as l on s.ingest_date = l.ingest_date
    where s.season >= {{ var('first_season') }}
),

abbr_map as (
    select
        feed_abbr,
        abbr
    from {{ ref('team_abbr_map') }}
)

select
    s.game_id,
    s.season,
    s.week,
    s.game_type,
    cast(s.gameday as date) as kickoff_date,
    coalesce(home_map.abbr, s.home_team) as home_team,
    coalesce(away_map.abbr, s.away_team) as away_team,
    s.home_score,
    s.away_score,
    coalesce(s.overtime = 1, false) as overtime,
    case
        when s.home_score is null or s.away_score is null then 'scheduled'
        else 'final'
    end as status
from schedules as s
left join abbr_map as home_map on s.home_team = home_map.feed_abbr
left join abbr_map as away_map on s.away_team = away_map.feed_abbr
