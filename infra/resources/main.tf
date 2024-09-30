terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-2"
}

# Variables
variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
  default     = "bucket-earthquake"
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "fetch-api-earthquake"
}

# Create an AWS ECR repository
resource "aws_ecr_repository" "earthquake_data_fetcher" {
  name = var.ecr_repository_name
}

# Create an S3 bucket for storing earthquake data CSVs
resource "aws_s3_bucket" "earthquake_data_bucket" {
  bucket = var.bucket_name
}

# Output the necessary variables for deployment
output "ecr_repo_url" {
  value       = aws_ecr_repository.earthquake_data_fetcher.repository_url
  description = "The URL of the ECR repository to push Docker images."
}

output "ecr_repo_arn" {
  value       = aws_ecr_repository.earthquake_data_fetcher.arn
  description = "The ARN of the ECR repository to push Docker images."
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.earthquake_data_bucket.bucket
  description = "The name of the S3 bucket where earthquake data will be stored."
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.earthquake_data_bucket.arn
  description = "The ARN of the S3 bucket where earthquake data will be stored."
}
