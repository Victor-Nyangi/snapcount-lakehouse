output "data_bucket" {
  value = aws_s3_bucket.data.bucket
}

output "athena_workgroup" {
  value = aws_athena_workgroup.lake.name
}

output "glue_databases" {
  value = [for layer in local.layers : aws_glue_catalog_database.layer[layer].name]
}

output "ingest_function_name" {
  value = aws_lambda_function.ingest.function_name
}
