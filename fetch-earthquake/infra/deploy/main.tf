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

variable "account_id" {
  type        = string
  description = "The AWS account ID."
}

variable "ecr_repo_url" {
  type        = string
  description = "The URL of the ECR repository containing the Docker image."
}

variable "ecr_repo_arn" {
  type        = string
  description = "The ARN of the ECR repository containing the Docker image."
}

variable "s3_bucket_arn" {
  type        = string
  description = "The ARN of the S3 bucket containing the earthquake data."
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
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
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
  function_name = "docker-lambda-function"
  role          = aws_iam_role.lambda_exec_role.arn

  package_type = "Image"
  image_uri    = "${var.ecr_repo_url}:latest"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.earthquake_success_topic.arn
    }
  }

  memory_size = 1024
  timeout     = 30
}

# Lambda permissions to allow invocation by S3
resource "aws_lambda_permission" "allow_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.docker_lambda.function_name
  principal     = "s3.amazonaws.com"
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
output "sns_topic_arn" {
  value       = aws_sns_topic.earthquake_success_topic.arn
  description = "The ARN of the SNS topic for earthquake data fetch success events."
}
