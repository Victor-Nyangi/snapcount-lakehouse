-- One row per (player_id, season, week, game_id): regular season only, no placeholder rows
-- (null player_id, about 22 a season), newest ingest per season, team codes mapped.

with ranked as (
    select
        p.player_id,
        p.player_name,
        p.player_display_name,
        p.position,
        p.team,
        p.season,
        p.week,
        p.season_type,
        p.game_id,
        p.attempts,
        p.carries,
        p.targets,
        p.receptions,
        p.passing_yards,
        p.passing_tds,
        p.passing_epa,
        p.rushing_yards,
        p.rushing_tds,
        p.rushing_epa,
        p.receiving_yards,
        p.receiving_tds,
        p.receiving_epa,
        p.ingest_date,
        max(p.ingest_date) over (partition by p.season) as latest_ingest_date
    from {{ source('bronze', 'player_week') }} as p
    where p.season >= {{ var('first_season') }}
),

abbr_map as (
    select
        feed_abbr,
        abbr
    from {{ ref('team_abbr_map') }}
)

select
    r.player_id,
    r.player_name,
    r.player_display_name,
    r.position,
    coalesce(m.abbr, r.team) as team,
    r.season,
    r.week,
    r.game_id,
    r.attempts,
    r.carries,
    r.targets,
    r.receptions,
    r.passing_yards,
    r.passing_tds,
    r.passing_epa,
    r.rushing_yards,
    r.rushing_tds,
    r.rushing_epa,
    r.receiving_yards,
    r.receiving_tds,
    r.receiving_epa
from ranked as r
left join abbr_map as m on r.team = m.feed_abbr
where
    r.ingest_date = r.latest_ingest_date
    and r.season_type = 'REG'
    and r.player_id is not null
