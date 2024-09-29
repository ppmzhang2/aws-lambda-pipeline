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

# Create an AWS ECR repository
resource "aws_ecr_repository" "earthquake_data_fetcher" {
  name = "earthquake-data-fetcher"
}

# Create an S3 bucket for storing earthquake data CSVs
resource "aws_s3_bucket" "earthquake_data_bucket" {
  bucket = "earthquake-data-bucket"
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
