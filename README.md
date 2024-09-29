# Earthquake Data Fetcher with AWS Lambda

This project fetches earthquake data from the USGS API, converts it into CSV format, and uploads it to an AWS S3 bucket. It uses a serverless approach with AWS Lambda and is containerized using Docker for deployment. The process of building and pushing the Docker image to AWS ECR is automated using GitHub Actions.

## Requirements

- Python 3.11
- Docker
- AWS account with permissions for Lambda, ECR, and S3.
- GitHub repository for CI/CD.

## Usage

1. Set up AWS ECR and S3

   - Create an ECR repository to store the Docker image.
   - Create an S3 bucket to store the earthquake data CSV files.

2. Build and Run Locally

   ```bash
   docker build -t earthquake-fetcher .
   docker run -e AWS_ACCESS_KEY_ID=<your-access-key> \
              -e AWS_SECRET_ACCESS_KEY=<your-secret-key> \
              earthquake-fetcher
   ```

3. Deploy with GitHub Actions

   - Configure GitHub secrets for AWS credentials and ECR repository details:

     - `AWS_ACCESS_KEY_ID`
     - `AWS_SECRET_ACCESS_KEY`
     - `AWS_REGION`
     - `AWS_ECR_REGISTRY`
     - `AWS_ECR_REPOSITORY`

   - Push changes to the `master` branch to trigger the CI/CD workflow.

4. Invoke the Lambda Function

   - Trigger the Lambda function with a JSON payload containing the desired `start_date`, `end_date`, and `bucket_name`.

   ```json
   {
     "start_date": "2020-01-01",
     "end_date": "2020-01-10",
     "bucket_name": "your-s3-bucket"
   }
   ```
