# One-time: the bucket that holds the lake stack's Terraform state.
# State for this stack itself stays local (infra/bootstrap/terraform.tfstate, gitignored);
# it holds one bucket and is never destroyed. Run with `make bootstrap`.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project   = "snapcount-lakehouse"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "snapcount-lake-tfstate-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
