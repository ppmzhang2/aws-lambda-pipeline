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

variable "lambda_role_arn" {
  type        = string
  description = "The ARN of the IAM role for the Lambda function."
}

variable "ecr_repository_url" {
  type        = string
  description = "The URL of the ECR repository containing the Docker image."
}

variable "account_id" {
  type        = string
  description = "The AWS account ID."
}

# Lambda deployment using Docker image from ECR
resource "aws_lambda_function" "docker_lambda" {
  function_name = "docker-lambda-function"
  role          = var.lambda_role_arn # IAM role ARN passed from the first terraform output

  package_type = "Image"
  image_uri    = "${var.ecr_repository_url}:latest" # ECR repository URL passed as a variable

  # Optional Lambda function settings
  memory_size = 1024
  timeout     = 30
}

# Optional Lambda permissions, such as invoking the Lambda function from API Gateway or S3
resource "aws_lambda_permission" "allow_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.docker_lambda.function_name
  principal     = "s3.amazonaws.com"
}

# Create an EventBridge rule that sends events to the default event bus
resource "aws_cloudwatch_event_rule" "lambda_earthquake_fetch_rule" {
  name        = "lambda-earthquake-fetch-success-rule"
  description = "Publish earthquake fetch success events to the default event bus"

  event_pattern = <<EOF
{
  "source": [
    "aws.logs"
  ],
  "detail-type": [
    "CloudWatch Logs Metric Filter"
  ],
  "detail": {
    "metrics": [
      {
        "metricName": "EarthquakeFetchSuccess",
        "namespace": "Earthquake/Metrics"
      }
    ]
  }
}
EOF
}

# Send the event to the default event bus
resource "aws_cloudwatch_event_target" "lambda_earthquake_fetch_target" {
  rule      = aws_cloudwatch_event_rule.lambda_earthquake_fetch_rule.name
  target_id = "EventBusTarget"
  arn       = "arn:aws:events:ap-southeast-2:${var.account_id}:event-bus/default"
}

# Permissions for EventBridge to send events to the event bus
resource "aws_lambda_permission" "allow_eventbridge_send" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.docker_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_earthquake_fetch_rule.arn
}

# Outputs (if needed)
output "lambda_function_name" {
  value       = aws_lambda_function.docker_lambda.function_name
  description = "The name of the Lambda function."
}
