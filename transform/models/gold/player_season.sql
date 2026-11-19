-- One row per (season, player_id): regular-season totals. Name, position and team come
-- from the player's latest week that season (a traded player shows their final team).

select
    season,
    player_id,
    max_by(coalesce(player_display_name, player_name, player_id), week) as player_display_name,
    max_by(position, week) as position,
    max_by(team, week) as team,
    count(*) as games,
    sum(coalesce(attempts, 0)) as attempts,
    sum(coalesce(carries, 0)) as carries,
    sum(coalesce(targets, 0)) as targets,
    sum(coalesce(receptions, 0)) as receptions,
    sum(coalesce(passing_yards, 0)) as passing_yards,
    sum(coalesce(passing_tds, 0)) as passing_tds,
    sum(coalesce(passing_epa, 0)) as passing_epa,
    sum(coalesce(rushing_yards, 0)) as rushing_yards,
    sum(coalesce(rushing_tds, 0)) as rushing_tds,
    sum(coalesce(rushing_epa, 0)) as rushing_epa,
    sum(coalesce(receiving_yards, 0)) as receiving_yards,
    sum(coalesce(receiving_tds, 0)) as receiving_tds,
    sum(coalesce(receiving_epa, 0)) as receiving_epa
from {{ ref('stg_player_weeks') }}
group by season, player_id
