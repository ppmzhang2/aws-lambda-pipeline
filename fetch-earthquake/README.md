# Earthquake Data Fetcher with AWS Lambda

This Lambda function fetches earthquake data from the USGS API, converts into
CSV format, and saves to the AWS S3 landing zone bucket.

## Usage

- Invoke manually with a JSON payload containing the desired `start_date`, `end_date`.

  ```json
  {
    "start_date": "2020-01-01",
    "end_date": "2020-01-10"
  }
  ```

- Schedule the Lambda function to run periodically with a CloudWatch Event Rule.
