"""Read all CSV files in a bucket."""

import json
import logging
import os

from aws_lambda_typing.context import Context
import boto3
import duckdb

logging.basicConfig(level=logging.INFO)

s3 = boto3.client("s3")


def handler(event: dict, context: Context) -> dict:  # noqa: ARG001
    """Lambda handler."""
    # Bucket name from event or hardcoded
    bucket_name = "your-s3-bucket-name"

    # List all objects in the S3 bucket
    try:
        response = s3.list_objects_v2(Bucket=bucket_name)
        if "Contents" not in response:
            return {
                "statusCode": 200,
                "body": json.dumps("No files in the bucket"),
            }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error listing objects in the bucket: {e!s}"),
        }

    total_row_count = 0
    for obj in response["Contents"]:
        key = obj["Key"]

        # Only process CSV files
        if key.endswith(".csv"):
            try:
                # Download the CSV file from S3 to Lambda's temp storage
                local_file_path = f"/tmp/{os.path.basename(key)}"
                s3.download_file(bucket_name, key, local_file_path)

                # Use DuckDB to count rows
                con = duckdb.connect()
                query = (
                    f"SELECT count(*) FROM read_csv_auto('{local_file_path}')")
                result = con.execute(query).fetchone()
                row_count = result[0]

                total_row_count += row_count
                logging.info(f"File: {key}, Row count: {row_count}")

                # Remove the local file after processing
                os.remove(local_file_path)
            except Exception:
                logging.exception(f"Error processing file {key}")

    # Prepare result as a txt file
    result_text = f"Total rows in all CSV files: {total_row_count}"
    result_key = "row_count_result.txt"

    try:
        # Upload the result back to the S3 bucket
        s3.put_object(Body=result_text, Bucket=bucket_name, Key=result_key)
        logging.info(f"Result saved to {result_key}")
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error uploading result to S3: {e!s}"),
        }

    return {
        "statusCode":
        200,
        "body":
        json.dumps(f"Total rows: {total_row_count}, saved to {result_key}"),
    }
