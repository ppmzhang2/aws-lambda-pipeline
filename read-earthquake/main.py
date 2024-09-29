"""Read all CSV files in a bucket."""

import json
import logging
import os

from aws_lambda_typing.context import Context
import boto3
import duckdb
import pandas as pd

logging.basicConfig(level=logging.INFO)

s3 = boto3.client("s3")
CHUNK_SIZE = 10000  # Maximum number of rows to read at once (chunk size)


def handler(event: dict, context: Context) -> dict:  # noqa: ARG001
    """Lambda handler triggered by S3 events."""
    # Extract the bucket name and key (file path) from the event
    record = event["Records"][0]
    input_bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]
    output_bucket = os.environ.get("OUTPUT_BUCKET", input_bucket)

    logging.info(f"Record: {record}; Bucket: {input_bucket}; Key: {key}")

    # Process the CSV file
    try:
        logging.info(f"Processing file: {key}")

        # Download the CSV file from S3 to Lambda's temp storage
        local_file_path = os.path.join(
            "/tmp",  # noqa: S108
            os.path.basename(key),
        )
        s3.download_file(input_bucket, key, local_file_path)

        # Process the CSV file in chunks to optimize memory usage
        row_count = process_csv_in_chunks(local_file_path)

        logging.info(f"File: {key}, Row count: {row_count}")

        # Remove the local file after processing
        os.remove(local_file_path)

        # Prepare result text and upload it back to S3
        result_text = f"Processed file {key}. Total rows: {row_count}"
        result_key = f"results/{os.path.basename(key)}_row_count.txt"
        s3.put_object(Body=result_text, Bucket=output_bucket, Key=result_key)
        logging.info(f"Result saved to {result_key}")

    except Exception as e:
        logging.exception(f"Error processing file {key}")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error processing file {key}: {e!s}"),
        }

    return {
        "statusCode":
        200,
        "body":
        json.dumps(
            f"Successfully processed file {key} with {row_count} rows."),
    }


def process_csv_in_chunks(file_path: str) -> int:
    """Process a CSV file in chunks and count the total rows using DuckDB."""
    # Initialize DuckDB connection and process file in chunks
    total_rows = 0
    try:
        con = duckdb.connect()

        # Use Pandas to read CSV in chunks and register each chunk with DuckDB
        for chunk in pd.read_csv(file_path, chunksize=CHUNK_SIZE):
            query = "SELECT COUNT(*) FROM chunk"
            con.register("chunk", chunk)
            result = con.execute(query).fetchone()
            total_rows += result[0]

    except Exception:
        logging.exception(f"Error processing CSV file {file_path}")

    return total_rows
