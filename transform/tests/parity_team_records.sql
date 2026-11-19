-- Rows only where a team's W-L-T for the parity season differs from snapcount's, including
-- a team that is in one side and missing from the other.

with expected as (
    select
        key as team,
        expected as expected_record
    from {{ ref('parity_expected_2025') }}
    where metric = 'team_record'
),

actual as (
    select
        team,
        cast(wins as varchar)
        || '-' || cast(losses as varchar)
        || '-' || cast(ties as varchar) as actual_record
    from {{ ref('team_season') }}
    where season = {{ var('parity_season') }}
)

select
    coalesce(e.team, a.team) as team,
    e.expected_record,
    a.actual_record
from expected as e
full outer join actual as a on e.team = a.team
where coalesce(e.expected_record, '') != coalesce(a.actual_record, '')
