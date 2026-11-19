provider "aws" {
  region = var.region
  # Credentials come from the environment (AWS_PROFILE=snapcount-lake via SSO). Nothing here.
}

data "aws_caller_identity" "current" {}
