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
variable "bucket_earthquake_raw" {
  description = "S3 bucket name for storing raw earthquake data"
  type        = string
  default     = "earthquake-raw"
}

variable "bucket_earthquake_processed" {
  description = "S3 bucket name for storing processed earthquake data"
  type        = string
  default     = "earthquake-processed"
}

variable "ecr_repo_fetch_earthquake" {
  description = "Name of the ECR repo for fetching earthquake raw data"
  type        = string
  default     = "fetch-api-earthquake"
}

variable "ecr_repo_process_earthquake" {
  description = "Name of the ECR repo for processing earthquake data"
  type        = string
  default     = "process-csv-earthquake"
}

# Create an AWS ECR repository (fetch earthquake data)
resource "aws_ecr_repository" "fetch_earthquake" {
  name = var.ecr_repo_fetch_earthquake
}

# Create an AWS ECR repository (process earthquake data)
resource "aws_ecr_repository" "process_earthquake" {
  name = var.ecr_repo_process_earthquake
}

# Create an S3 bucket for storing earthquake data CSVs
resource "aws_s3_bucket" "earthquake_raw" {
  bucket = var.bucket_earthquake_raw
}

# Create an S3 bucket for storing processed earthquake data
resource "aws_s3_bucket" "earthquake_processed" {
  bucket = var.bucket_earthquake_processed
}

# Output the necessary variables for deployment
output "ecr_fetch_earthquake_url" {
  value       = aws_ecr_repository.fetch_earthquake.repository_url
  description = "The URL of the ECR repo for fetching earthquake raw data."
}

output "ecr_fetch_earthquake_arn" {
  value       = aws_ecr_repository.fetch_earthquake.arn
  description = "The ARN of the ECR repo for fetching earthquake raw data."
}

output "ecr_process_earthquake_url" {
  value       = aws_ecr_repository.process_earthquake.repository_url
  description = "The URL of the ECR repo for processing earthquake raw data."
}

output "ecr_process_earthquake_arn" {
  value       = aws_ecr_repository.process_earthquake.arn
  description = "The ARN of the ECR repo for processing earthquake raw data."
}

output "s3_bucket_raw_earthquake_arn" {
  value       = aws_s3_bucket.earthquake_raw.arn
  description = "ARN of the S3 bucket for raw earthquake data."
}

output "s3_bucket_raw_earthquake_id" {
  value       = aws_s3_bucket.earthquake_raw.id
  description = "ID of the S3 bucket for raw earthquake data."
}

output "s3_bucket_processed_earthquake_arn" {
  value       = aws_s3_bucket.earthquake_processed.arn
  description = "ARN of the S3 bucket for processed earthquake data."
}

output "s3_bucket_processed_earthquake_id" {
  value       = aws_s3_bucket.earthquake_processed.id
  description = "ID of the S3 bucket for processed earthquake data."
}
