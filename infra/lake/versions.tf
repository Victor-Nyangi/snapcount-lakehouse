terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }

  # Bucket comes from `make up` (-backend-config=bucket=snapcount-lake-tfstate-<account_id>)
  # so no account id is committed. use_lockfile = S3-native locking, no DynamoDB table.
  backend "s3" {
    key          = "lake/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
