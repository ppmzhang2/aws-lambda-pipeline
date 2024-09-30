# Earthquake Data Fetcher with AWS Lambda

This project fetches earthquake data from the USGS API, converts it into CSV format, and uploads it to an AWS S3 bucket. It uses a serverless approach with AWS Lambda and is containerized using Docker for deployment. The process of building and pushing the Docker image to AWS ECR is automated using GitHub Actions.

## Requirements

- Python 3.11
- Docker
- AWS account with permissions for Lambda, ECR, and S3.
- GitHub repository for CI/CD.

## Usage

- Set up AWS Resources by applying the Terraform configuration in the `infra/resources` directory.

  ```bash
  cd infra/resources
  terraform init
  terraform apply
  ```

- Deploy with GitHub Actions

  - Configure GitHub secrets for AWS credentials and ECR repository details:

    - `AWS_REGION`
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `AWS_ECR_REGISTRY`
    - `AWS_ECR_REPOSITORY`

  - Push changes to the `master` branch to trigger the CI/CD workflow.

- Invoke the Lambda Function

  - Trigger the Lambda function with a JSON payload containing the desired `start_date`, `end_date`, and `bucket_name`.

  ```json
  {
    "start_date": "2020-01-01",
    "end_date": "2020-01-10",
    "bucket_name": "bucket-earthquake"
  }
  ```
