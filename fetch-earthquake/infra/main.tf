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
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region"
  default     = "ap-southeast-2"
}

variable "account_id" {
  type        = string
  description = "The AWS account ID"
}

variable "ecr_repo_id" {
  type        = string
  description = "The ID of the ECR repository containing the Docker image."
}

variable "s3_bucket_id" {
  type        = string
  description = "The ID of the S3 bucket containing raw earthquake data."
  default     = "earthquake-raw"
}

variable "lambda_role_name" {
  type        = string
  description = "The name of the IAM role for Lambda execution."
  default     = "role-fetch-raw-earthquake"
}

variable "lambda_func_name" {
  type        = string
  description = "The name of the Lambda function."
  default     = "func-fetch-earthquake"
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_exec_role" {
  name = var.lambda_role_name

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
          "arn:aws:s3:::${var.s3_bucket_id}",
          "arn:aws:s3:::${var.s3_bucket_id}/*"
        ]
      },
      {
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.ecr_repo_id}"
      }
    ]
  })
}

# Attach ECR policies to the Lambda execution role
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
        Resource = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.ecr_repo_id}"
      },
      {
        Action   = "ecr:GetAuthorizationToken",
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Lambda function deployed with a Docker image from ECR
resource "aws_lambda_function" "docker_lambda" {
  function_name = var.lambda_func_name
  role          = aws_iam_role.lambda_exec_role.arn

  package_type = "Image"
  image_uri    = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo_id}:latest"

  environment {
    variables = {
      BUCKET_NAME   = var.s3_bucket_id
    }
  }

  memory_size = 1024
  timeout     = 120
}

# CloudWatch Log Group for Lambda Function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.docker_lambda.function_name}"
  retention_in_days = 14
}

# Outputs
output "lambda_function_arn" {
  value       = aws_lambda_function.docker_lambda.arn
  description = "The ARN of the Lambda function."
}
