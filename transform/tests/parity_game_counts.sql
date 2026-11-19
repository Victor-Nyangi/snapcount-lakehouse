-- Rows only where the lake's game count for the parity season differs from snapcount's.
-- games/REG is regular season; games/POST is every other game_type (WC, DIV, CON, SB).

with expected as (
    select
        key as game_class,
        cast(expected as bigint) as expected_games
    from {{ ref('parity_expected_2025') }}
    where metric = 'games'
),

classified as (
    select case when game_type = 'REG' then 'REG' else 'POST' end as game_class
    from {{ ref('stg_games') }}
    where season = {{ var('parity_season') }}
),

actual as (
    select
        game_class,
        count(*) as actual_games
    from classified
    group by game_class
)

select
    coalesce(e.game_class, a.game_class) as game_class,
    e.expected_games,
    a.actual_games
from expected as e
full outer join actual as a on e.game_class = a.game_class
where coalesce(e.expected_games, -1) != coalesce(a.actual_games, 0)
