terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Remote State Storage with S3 & DynamoDB State Locking (Question 4.e)
  # Run ./bootstrap-backend.sh once per environment, then initialize via:
  #   terraform init -backend-config=backend.hcl -reconfigure
  # (-backend=false is for offline fmt/validate syntax checks only)
  backend "s3" {}
}
