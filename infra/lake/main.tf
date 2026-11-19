locals {
  name = "snapcount-lake"

  tags = {
    Project   = "snapcount-lakehouse"
    ManagedBy = "terraform"
  }

  account_id  = data.aws_caller_identity.current.account_id
  data_bucket = "${local.name}-data-${local.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.data_bucket}"
}
