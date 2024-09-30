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

variable "ecr_image_url" {
  description = "URL of the Docker image in ECR for the Lambda function"
  type        = string
}

variable "input_bucket_name" {
  description = "The name of the S3 bucket where CSV files are uploaded"
  type        = string
  default     = "bucket-earthquake"
}

variable "output_bucket_name" {
  description = "The name of the S3 bucket where processed results are stored"
  type        = string
  default     = "earthquake-processed"
}

variable "lambda_role_name" {
  description = "The name of the IAM role for the Lambda function"
  type        = string
  default     = "lambda_s3_processor_role"
}

variable "lambda_function_name" {
  description = "The name of the Lambda function"
  type        = string
  default     = "csv_processor_lambda"
}

variable "lambda_policy_name" {
  description = "The name of the IAM policy for the Lambda function"
  type        = string
  default     = "policy_lambda_process_earthquake"
}

resource "aws_iam_role" "lambda_role" {
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

resource "aws_iam_policy" "lambda_policy" {
  name = var.lambda_policy_name

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
        Action   = "s3:PutObject",
        Effect   = "Allow",
        Resource = "arn:aws:s3:::${var.output_bucket_name}/*"
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

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "csv_processor_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = var.ecr_image_url

  environment {
    variables = {
      OUTPUT_BUCKET = var.output_bucket_name
    }
  }

  timeout     = 300
  memory_size = 512
}

resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_processor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

resource "aws_s3_bucket_notification" "s3_to_lambda" {
  bucket = aws_s3_bucket.input_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_processor_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}
