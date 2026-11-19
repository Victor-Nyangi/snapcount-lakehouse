-- One row if the lake's player-season count for the parity season differs from snapcount's
-- (or if the seed row is missing).

with expected as (
    select cast(expected as bigint) as expected_player_seasons
    from {{ ref('parity_expected_2025') }}
    where metric = 'player_seasons' and key = 'all'
),

actual as (
    select count(*) as actual_player_seasons
    from {{ ref('player_season') }}
    where season = {{ var('parity_season') }}
)

select
    e.expected_player_seasons,
    a.actual_player_seasons
from actual as a
left join expected as e on true
where coalesce(e.expected_player_seasons, -1) != a.actual_player_seasons
