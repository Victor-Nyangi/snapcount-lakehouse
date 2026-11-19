# What snapcount-lakehouse costs

The target is under $1 a month with the stack up, and $0 with it down (only the state bucket,
a few KB, survives `make down`). The AWS Budget `snapcount-lake-monthly` emails at 80% of $5
actual and 100% of $5 forecast.

## How to measure

```bash
make cost      # last 30 days: Project-tagged spend, then the whole account by service
make scanned   # Athena bytes scanned by the last dbt invocation
```

The tag-filtered number needs `Project` activated as a cost allocation tag and lags by up to a
day. In a dedicated account the by-service table is the one to trust.

## Expected, before any real run

| Service | Driver | Unit price (eu-west-1) | Expected per month |
|---|---|---|---|
| S3 storage | ~1.4 MB per ingest (games.parquet 0.52 MB, stats_player_week_2025 0.86 MB) plus Iceberg files | ~$0.023 per GB-month | < $0.01 |
| S3 requests | ingest PUT/LIST, Athena GET/LIST | ~$0.005 per 1,000 PUT/LIST | < $0.01 |
| Athena | 10 MB minimum billed per query; a `dbt build` is ~50-80 queries | $5 per TB scanned | < $0.01 per build |
| Lambda | a few 256 MB invocations of a few seconds | free tier | $0.00 |
| Glue Data Catalog | ~10 tables, few requests | free tier (1M objects, 1M requests) | $0.00 |
| CloudWatch Logs | one log line per invocation, 14-day retention | ~$0.57 per GB ingested | < $0.01 |
| AWS Budgets | one budget | first two free | $0.00 |

## Measured

Fill in from `make cost` and `make scanned` during Task 6.

| Date | Event | Athena scanned | Cost so far (tagged) | Cost so far (account) | Notes |
|---|---|---|---|---|---|
| | first `make up` + `ingest` + `build` | | | | |
| | `make down`, then full rebuild | | | | |
| | +7 days (`make cost`) | | | | target: < $0.25 |
