locals {
  layers = ["bronze", "silver", "gold"]

  # Bronze declares only the source columns snapcount uses. Types match the nflverse
  # Parquet schema (int32 -> int, double, string), checked against the 2025 files.
  bronze = {
    schedules = {
      partitions = [{ name = "ingest_date", type = "string" }]
      template   = "s3://${local.data_bucket}/raw/schedules/ingest_date=$${ingest_date}/"
      columns = [
        { name = "game_id", type = "string" },
        { name = "season", type = "int" },
        { name = "week", type = "int" },
        { name = "game_type", type = "string" },
        { name = "gameday", type = "string" },
        { name = "gametime", type = "string" },
        { name = "away_team", type = "string" },
        { name = "home_team", type = "string" },
        { name = "away_score", type = "int" },
        { name = "home_score", type = "int" },
        { name = "spread_line", type = "double" },
        { name = "total_line", type = "double" },
        { name = "overtime", type = "int" },
      ]
    }
    player_week = {
      partitions = [
        { name = "season", type = "int" },
        { name = "ingest_date", type = "string" },
      ]
      template = "s3://${local.data_bucket}/raw/player_week/season=$${season}/ingest_date=$${ingest_date}/"
      # `season` is also a column inside the file; it is the partition key here, which
      # Athena fills from the path. The two always agree (one file per season).
      columns = [
        { name = "player_id", type = "string" },
        { name = "player_name", type = "string" },
        { name = "player_display_name", type = "string" },
        { name = "position", type = "string" },
        { name = "team", type = "string" },
        { name = "week", type = "int" },
        { name = "season_type", type = "string" },
        { name = "game_id", type = "string" },
        { name = "attempts", type = "int" },
        { name = "carries", type = "int" },
        { name = "targets", type = "int" },
        { name = "receptions", type = "int" },
        { name = "passing_yards", type = "int" },
        { name = "passing_tds", type = "int" },
        { name = "passing_epa", type = "double" },
        { name = "rushing_yards", type = "int" },
        { name = "rushing_tds", type = "int" },
        { name = "rushing_epa", type = "double" },
        { name = "receiving_yards", type = "int" },
        { name = "receiving_tds", type = "int" },
        { name = "receiving_epa", type = "double" },
      ]
    }
  }

  projection_common = {
    "projection.enabled"                   = "true"
    "projection.ingest_date.type"          = "date"
    "projection.ingest_date.format"        = "yyyy-MM-dd"
    "projection.ingest_date.range"         = "${var.ingest_date_projection_start},NOW"
    "projection.ingest_date.interval"      = "1"
    "projection.ingest_date.interval.unit" = "DAYS"
  }

  projection_extra = {
    schedules = {}
    player_week = {
      "projection.season.type"  = "integer"
      "projection.season.range" = "2016,2030"
    }
  }
}

resource "aws_glue_catalog_database" "layer" {
  for_each    = toset(local.layers)
  name        = "snapcount_lake_${each.key}"
  description = "snapcount-lakehouse ${each.key} layer"
  tags        = local.tags
}

# Partition projection: Athena works out partitions from the path template, so there is no
# Glue crawler and no MSCK REPAIR. Files starting with "_" (the manifests) are ignored.
resource "aws_glue_catalog_table" "bronze" {
  for_each      = local.bronze
  name          = each.key
  database_name = aws_glue_catalog_database.layer["bronze"].name
  table_type    = "EXTERNAL_TABLE"

  parameters = merge(
    {
      "EXTERNAL"                  = "TRUE"
      "classification"            = "parquet"
      "parquet.compression"       = "SNAPPY"
      "storage.location.template" = each.value.template
    },
    local.projection_common,
    local.projection_extra[each.key],
  )

  dynamic "partition_keys" {
    for_each = each.value.partitions
    content {
      name = partition_keys.value.name
      type = partition_keys.value.type
    }
  }

  storage_descriptor {
    location      = "s3://${local.data_bucket}/raw/${each.key}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = each.value.columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}
