# Plan-only tests against a mocked AWS provider: no credentials, no API calls.
# Run: terraform -chdir=infra/lake init -backend=false && terraform -chdir=infra/lake test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
}

mock_provider "archive" {}

variables {
  budget_email = "budget-alerts@example.com"
}

run "athena_guardrails" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.lake.name == "snapcount-lake"
    error_message = "workgroup must be named snapcount-lake"
  }

  assert {
    condition     = aws_athena_workgroup.lake.configuration[0].bytes_scanned_cutoff_per_query == 1073741824
    error_message = "every query must be capped at 1 GB scanned"
  }

  assert {
    condition     = aws_athena_workgroup.lake.configuration[0].enforce_workgroup_configuration == true
    error_message = "clients must not be able to override the workgroup settings"
  }

  assert {
    condition     = aws_athena_workgroup.lake.configuration[0].result_configuration[0].output_location == "s3://snapcount-lake-data-000000000000/athena-results/"
    error_message = "query results must land under athena-results/ in the data bucket"
  }
}

run "data_bucket_is_private_and_expiring" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.data.block_public_acls,
      aws_s3_bucket_public_access_block.data.block_public_policy,
      aws_s3_bucket_public_access_block.data.ignore_public_acls,
      aws_s3_bucket_public_access_block.data.restrict_public_buckets,
    ])
    error_message = "all four public access block flags must be true"
  }

  # Rules are checked by index, not with a for-expression over the whole rule list:
  # Terraform 1.17.2 panics while rendering a *failed* assertion that references the full
  # mocked list (inconsistent element types). Rule order is fixed in s3.tf.
  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.data.rule[1].id == "athena-results" &&
      aws_s3_bucket_lifecycle_configuration.data.rule[1].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.data.rule[1].filter[0].prefix == "athena-results/" &&
      aws_s3_bucket_lifecycle_configuration.data.rule[1].expiration[0].days == 7
    )
    error_message = "athena-results/ must expire after 7 days"
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.data.rule[0].id == "raw-old-versions" &&
      aws_s3_bucket_lifecycle_configuration.data.rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.data.rule[0].filter[0].prefix == "raw/" &&
      aws_s3_bucket_lifecycle_configuration.data.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    )
    error_message = "old versions under raw/ must expire after 30 days"
  }

  assert {
    condition     = aws_s3_bucket_versioning.data.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be on so raw/ objects can't be lost"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.data.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "data bucket must use SSE-S3"
  }

  assert {
    condition     = aws_s3_bucket.data.force_destroy == true
    error_message = "the data bucket is rebuildable from source, so make down must be able to empty it"
  }
}

run "budget" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.name == "snapcount-lake-monthly"
    error_message = "budget must be named snapcount-lake-monthly"
  }

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "5"
    error_message = "budget must be $5"
  }

  assert {
    condition = anytrue([
      for n in aws_budgets_budget.monthly.notification :
      n.notification_type == "ACTUAL" && n.threshold == 80 && contains(n.subscriber_email_addresses, "budget-alerts@example.com")
    ])
    error_message = "budget must email at 80% of actual spend"
  }

  assert {
    condition = anytrue([
      for n in aws_budgets_budget.monthly.notification :
      n.notification_type == "FORECASTED" && n.threshold == 100
    ])
    error_message = "budget must email at 100% of forecast"
  }
}

run "glue_and_bronze" {
  command = plan

  assert {
    condition = toset([for d in aws_glue_catalog_database.layer : d.name]) == toset([
      "snapcount_lake_bronze", "snapcount_lake_silver", "snapcount_lake_gold",
    ])
    error_message = "bronze, silver and gold Glue databases must exist"
  }

  assert {
    condition     = aws_glue_catalog_table.bronze["player_week"].parameters["projection.season.range"] == "2016,2030"
    error_message = "player_week must project seasons 2016-2030"
  }

  assert {
    condition     = aws_glue_catalog_table.bronze["player_week"].parameters["storage.location.template"] == "s3://snapcount-lake-data-000000000000/raw/player_week/season=$${season}/ingest_date=$${ingest_date}/"
    error_message = "player_week location template must match the ingest key layout"
  }

  assert {
    condition     = aws_glue_catalog_table.bronze["schedules"].parameters["storage.location.template"] == "s3://snapcount-lake-data-000000000000/raw/schedules/ingest_date=$${ingest_date}/"
    error_message = "schedules location template must match the ingest key layout"
  }

  assert {
    condition     = [for k in aws_glue_catalog_table.bronze["schedules"].partition_keys : k.name] == ["ingest_date"]
    error_message = "schedules is partitioned by ingest_date only"
  }

  assert {
    condition     = [for k in aws_glue_catalog_table.bronze["player_week"].partition_keys : k.name] == ["season", "ingest_date"]
    error_message = "player_week is partitioned by season, then ingest_date"
  }
}

run "ingest_lambda" {
  command = plan

  assert {
    condition     = aws_lambda_function.ingest.function_name == "snapcount-lake-ingest"
    error_message = "lambda must be named snapcount-lake-ingest"
  }

  assert {
    condition     = aws_lambda_function.ingest.runtime == "python3.13" && aws_lambda_function.ingest.memory_size == 256 && aws_lambda_function.ingest.timeout == 300
    error_message = "lambda must be python3.13, 256 MB, 300 s"
  }

  assert {
    condition     = aws_lambda_function.ingest.handler == "lake_ingest.handler.handler"
    error_message = "lambda handler must point at lake_ingest.handler.handler"
  }

  assert {
    condition     = aws_lambda_function.ingest.environment[0].variables["LAKE_BUCKET"] == "snapcount-lake-data-000000000000"
    error_message = "lambda must know the data bucket"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.ingest.policy).Statement :
      alltrue([for r in flatten([s.Resource]) : r != "*"])
    ])
    error_message = "the ingest role must not have wildcard resources"
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.ingest.policy).Statement : flatten([s.Action])
      ])) == toset([
      "s3:PutObject", "s3:GetObject", "s3:ListBucket", "logs:CreateLogStream", "logs:PutLogEvents",
    ])
    error_message = "the ingest role may only put/get/list objects and write logs"
  }
}

run "every_taggable_resource_carries_project_tag" {
  command = plan

  assert {
    condition = alltrue([
      for tags in concat(
        [
          aws_s3_bucket.data.tags,
          aws_athena_workgroup.lake.tags,
          aws_lambda_function.ingest.tags,
          aws_iam_role.ingest.tags,
          aws_cloudwatch_log_group.ingest.tags,
          aws_budgets_budget.monthly.tags,
        ],
        [for d in aws_glue_catalog_database.layer : d.tags],
      ) : tags["Project"] == "snapcount-lakehouse" && tags["ManagedBy"] == "terraform"
    ])
    error_message = "every taggable resource must carry Project=snapcount-lakehouse and ManagedBy=terraform"
  }

  assert {
    condition     = output.glue_databases == ["snapcount_lake_bronze", "snapcount_lake_silver", "snapcount_lake_gold"]
    error_message = "glue_databases output must list bronze, silver, gold in order"
  }
}
