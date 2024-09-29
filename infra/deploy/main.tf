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

# Lambda deployment using Docker image from ECR
resource "aws_lambda_function" "docker_lambda" {
  function_name = "docker-lambda-function"
  role          = var.lambda_role_arn  # IAM role ARN passed from the first terraform output

  package_type = "Image"
  image_uri    = "${var.ecr_repository_url}:latest"  # ECR repository URL passed as a variable

  # Optional Lambda function settings
  memory_size     = 1024
  timeout         = 30
}

# Optional Lambda permissions, such as invoking the Lambda function from API Gateway or S3
resource "aws_lambda_permission" "allow_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.docker_lambda.function_name
  principal     = "s3.amazonaws.com"
}

# Outputs (if needed)
output "lambda_function_name" {
  value       = aws_lambda_function.docker_lambda.function_name
  description = "The name of the Lambda function."
}
