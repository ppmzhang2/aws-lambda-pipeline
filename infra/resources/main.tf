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

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach the necessary policies to the Lambda execution role
resource "aws_iam_role_policy" "lambda_exec_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          aws_s3_bucket.earthquake_data_bucket.arn,
          "${aws_s3_bucket.earthquake_data_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ],
        Effect   = "Allow",
        Resource = aws_ecr_repository.earthquake_data_fetcher.arn
      }
    ]
  })
}

# Lambda execution policy for ECR access
resource "aws_iam_role_policy" "ecr_lambda_exec_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ],
        Effect   = "Allow",
        Resource = aws_ecr_repository.earthquake_data_fetcher.arn
      },
      {
        Action   = "ecr:GetAuthorizationToken",
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Create a CloudWatch Log Group for Lambda A
resource "aws_cloudwatch_log_group" "lambda_a_log_group" {
  name              = "/aws/lambda/docker-lambda-function"
  retention_in_days = 14
}

# Define a CloudWatch Log Metric Filter to monitor successful Lambda executions
resource "aws_cloudwatch_log_metric_filter" "lambda_a_success_metric" {
  name           = "lambda_a_success_metric"
  log_group_name = aws_cloudwatch_log_group.lambda_a_log_group.name

  pattern = "\"CSV file successfully uploaded\""

  metric_transformation {
    name      = "LambdaASuccessMetric"
    namespace = "LambdaA/Metrics"
    value     = "1"
  }
}

# Output the necessary variables for deployment
output "ecr_repository_url" {
  value       = aws_ecr_repository.earthquake_data_fetcher.repository_url
  description = "The URL of the ECR repository to push Docker images."
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.earthquake_data_bucket.bucket
  description = "The name of the S3 bucket where earthquake data will be stored."
}

output "lambda_role_arn" {
  value       = aws_iam_role.lambda_exec_role.arn
  description = "The ARN of the IAM Role assigned to the Lambda function."
}
