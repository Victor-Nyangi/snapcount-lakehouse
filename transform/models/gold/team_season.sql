-- One row per (season, team). Only regular-season games with status 'final' count, so
-- unplayed games (null scores) and the postseason never touch a record.

with reg_games as (
    select
        season,
        home_team,
        away_team,
        home_score,
        away_score,
        status
    from {{ ref('stg_games') }}
    where game_type = 'REG'
),

teams as (
    select
        season,
        home_team as team
    from reg_games
    union distinct
    select
        season,
        away_team as team
    from reg_games
),

results as (
    select
        season,
        home_team as team,
        home_score as points_for,
        away_score as points_against
    from reg_games
    where status = 'final'
    union all
    select
        season,
        away_team as team,
        away_score as points_for,
        home_score as points_against
    from reg_games
    where status = 'final'
)

select
    t.season,
    t.team,
    count_if(r.points_for > r.points_against) as wins,
    count_if(r.points_for < r.points_against) as losses,
    count_if(r.points_for = r.points_against) as ties,
    coalesce(sum(r.points_for), 0) as points_for,
    coalesce(sum(r.points_against), 0) as points_against,
    count(r.team) as games_played
from teams as t
left join results as r
    on t.season = r.season and t.team = r.team
group by t.season, t.team
