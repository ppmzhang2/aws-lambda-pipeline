# Earthquake Data Processor with AWS Lambda

This Lambda function automatically processes newly added raw CSV earthquake.

## Features

- Automatically triggered with S3 events when a `.csv` file is added to the
  specified S3 input bucket. It processes the file, and stores the result in
  the output S3 bucket.

- Read the files in chunks to optimize memory usage and uploads the results to
  another S3 bucket.

- Logs are stored in an associated CloudWatch Log Group. These logs can be used
  for debugging and monitoring the function’s performance.
