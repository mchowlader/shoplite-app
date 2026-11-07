terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Remote State Storage with DynamoDB State Locking (Requirement 4.e)
  # Uncomment and configure with your Poridhi S3 bucket and DynamoDB table
  # backend "s3" {
  #   bucket         = "shoplite-terraform-state-ap-southeast-1"
  #   key            = "shoplite/production/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   dynamodb_table = "shoplite-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = "shoplite"
      environment = var.environment
      managed_by  = "terraform"
    }
  }
}
