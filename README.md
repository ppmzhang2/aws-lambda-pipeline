# AWS Lambda Functions Pipeline

## Requirements

- Python 3.11
- Docker
- AWS account with permissions for Lambda, ECR, and S3.
- GitHub repository for CI/CD.

## Usage

- Set up AWS Resources by applying the Terraform configuration in the `infra`
  directory.

  ```bash
  cd infra/
  terraform init
  terraform apply
  ```

- Deploy with GitHub Actions

  - The docker images will be automatically built and pushed to the ECR
    repository by the GitHub Actions workflow, before deployed as a Lambda
    function.

  - Configure GitHub secrets for AWS credentials and ECR repository details:

    - `AWS_REGION`
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `AWS_ECR_REGISTRY`
    - `AWS_ECR_REPO_FETCHEQ`
    - `AWS_ECR_REPO_PROCESSEQ`

  - Push changes to the `master` branch to trigger the CI/CD workflow.

- Invoke the Lambda functions

  It contains two Lambda functions:

  - `fetch-earthquake`: fetch raw earthquake data from the USGS API and store
    it in an S3 bucket landing zone.

  - `process-earthquake`: process the raw earthquake data triggered by the S3
    event and store the processed data in another S3 bucket.
