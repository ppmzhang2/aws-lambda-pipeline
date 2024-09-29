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

variable "ecr_repo_url" {
  type        = string
  description = "The URL of the ECR repository containing the Docker image."
}

variable "ecr_repo_arn" {
  type        = string
  description = "The ARN of the ECR repository containing the Docker image."
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
        Resource = var.ecr_repo_arn
      },
      {
        Action = [
          "sns:Publish"
        ],
        Effect   = "Allow",
        Resource = aws_sns_topic.earthquake_success_topic.arn
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
        Resource = var.ecr_repo_arn
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
  image_uri    = "${var.ecr_repo_url}:latest"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.earthquake_success_topic.arn
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

# SNS Topic for earthquake data success events
resource "aws_sns_topic" "earthquake_success_topic" {
  name = "earthquake-success-topic"
}

# Grant permissions for EventBridge to publish to SNS (if needed in the future)
resource "aws_sns_topic_policy" "earthquake_success_topic_policy" {
  arn    = aws_sns_topic.earthquake_success_topic.arn
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sns:Publish",
      "Resource": "${aws_sns_topic.earthquake_success_topic.arn}"
    }
  ]
}
EOF
}

# Outputs
output "lambda_function_arn" {
  value       = aws_lambda_function.docker_lambda.arn
  description = "The ARN of the Lambda function."
}

output "sns_topic_arn" {
  value       = aws_sns_topic.earthquake_success_topic.arn
  description = "The ARN of the SNS topic for earthquake data fetch success events."
}
