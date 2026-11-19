# The ingest package is stdlib-only (boto3 ships with the runtime), so Terraform zips
# ingest/lake_ingest/*.py itself under a lake_ingest/ prefix. No separate build step.
data "archive_file" "ingest" {
  type        = "zip"
  output_path = "${path.module}/../../build/ingest.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/../../ingest/lake_ingest", "*.py")
    content {
      filename = "lake_ingest/${source.value}"
      content  = file("${path.module}/../../ingest/lake_ingest/${source.value}")
    }
  }
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${local.name}-ingest"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_iam_role" "ingest" {
  name = "${local.name}-ingest"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least privilege: read and add objects under raw/ (bronze) and runs/ (ingest log), list
# only those prefixes, write its own logs. No delete, no other prefixes, no other buckets.
resource "aws_iam_role_policy" "ingest" {
  name = "${local.name}-ingest"
  role = aws_iam_role.ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadWriteBronzeAndRunLog"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${local.bucket_arn}/raw/*", "${local.bucket_arn}/runs/*"]
      },
      {
        Sid       = "ListBronzeAndRunLog"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = [local.bucket_arn]
        Condition = { StringLike = { "s3:prefix" = ["raw/*", "runs/*"] } }
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${local.name}-ingest:*"]
      },
    ]
  })
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${local.name}-ingest"
  role             = aws_iam_role.ingest.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "lake_ingest.handler.handler"
  memory_size      = 256
  timeout          = 300
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      LAKE_BUCKET = local.data_bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.ingest, aws_iam_role_policy.ingest]
}
