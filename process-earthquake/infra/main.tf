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

variable "email_addr" {
  type        = string
  description = "The email address for SNS notifications"
}

variable "input_bucket_name" {
  type        = string
  description = "The name of the S3 bucket where CSV files are uploaded"
  default     = "earthquake-raw"
}

variable "output_bucket_name" {
  type        = string
  description = "The name of the S3 bucket where processed results are stored"
  default     = "earthquake-processed"
}

variable "lambda_role_name" {
  type        = string
  description = "The name of the IAM role for the Lambda function"
  default     = "role-process-csv-earthquake"
}

variable "lambda_func_name" {
  type        = string
  description = "The name of the Lambda function"
  default     = "func-process-csv-earthquake"
}

variable "sns_topic_name" {
  type        = string
  description = "The name of the SNS topic for alarm notifications"
  default     = "fail-csv-processor"
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
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::${var.input_bucket_name}",
          "arn:aws:s3:::${var.input_bucket_name}/*"
        ]
      },
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::${var.output_bucket_name}",
          "arn:aws:s3:::${var.output_bucket_name}/*"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
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
resource "aws_lambda_function" "csv_processor" {
  function_name = var.lambda_func_name
  role          = aws_iam_role.lambda_exec_role.arn

  package_type = "Image"
  image_uri    = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo_id}:latest"

  environment {
    variables = {
      INPUT_BUCKET  = var.input_bucket_name
      OUTPUT_BUCKET = var.output_bucket_name
    }
  }

  memory_size = 3008 # max memory size
  timeout     = 300

  ephemeral_storage {
    size = 8192 # 8GB
  }
}

# CloudWatch Log Group for Lambda Function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.csv_processor.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.input_bucket_name}"
}

resource "aws_s3_bucket_notification" "s3_to_lambda" {
  bucket = var.input_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "error_msg_csv_processor" {
  name = var.sns_topic_name
}

# Create SNS subscription (e.g., email)
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.error_msg_csv_processor.arn
  protocol  = "email"
  endpoint  = var.email_addr
}

# CloudWatch Alarm for Lambda Errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "alarm-fail-lambda-csv-processor"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    FunctionName = aws_lambda_function.csv_processor.function_name
  }

  alarm_actions = [
    aws_sns_topic.error_msg_csv_processor.arn
  ]

  treat_missing_data = "notBreaching"
}
