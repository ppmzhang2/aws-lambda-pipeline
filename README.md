# AWS Lambda Pipeline for Earthquake Data Processing

This repository demonstrates a serverless pipeline that collects, processes, and stores data from API using AWS Lambda, S3, Docker, and GitHub Actions.

The pipeline consists of two AWS Lambda functions:

- `fetch-earthquake`: Fetch raw earthquake data from the USGS API, convert to CSV, and store in S3.
- `process-earthquake`: Process the CSV data, convert it to partitioned Parquet format, and save back to S3.

Key Features:

- **Terraform** provisions AWS infrastructure (Lambda, S3, ECR).
- **GitHub Actions** automates CI/CD for Docker image build and deployment.
- **Event-driven** processing with S3-triggered Lambda functions.

Requirements:

- Python 3.11
- Docker
- AWS account with permissions for Lambda, ECR, and S3
- GitHub repository for CI/CD

## Usage

### Infrastructure Setup

Provision AWS resources with Terraform:

```bash
cd infra/
terraform init
terraform apply
```

### Deploying with GitHub Actions

Configure GitHub secrets for AWS credentials and ECR details:

- `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `AWS_ECR_REGISTRY`, `AWS_ECR_REPO_FETCHEQ`, `AWS_ECR_REPO_PROCESSEQ`

Push changes to the `master` branch to trigger deployment.

### Invoking the Functions

- `fetch-earthquake`: Triggered manually or by a scheduler (e.g., `EventBridge`).
- `process-earthquake`: Automatically triggered by S3 event when a CSV is uploaded.

### Scaling for Production

For horizontal scaling in a production environment, additional services can be integrated (e.g., using SFTP to transfer data to S3) to enhance the pipeline's capabilities.
