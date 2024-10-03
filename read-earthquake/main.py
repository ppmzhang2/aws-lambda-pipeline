"""Read a S3 CSV file, convert to partitioned Parquet and save back to S3."""

import json
import logging
import os

from aws_lambda_typing.context import Context
import boto3
import duckdb

logging.basicConfig(level=logging.INFO)

s3 = boto3.client("s3")


def receive_s3_event(event: dict) -> tuple[str, str]:
    """Receive an S3 event and extract the bucket and key."""
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]
    return bucket, key


def handler(event: dict, context: Context) -> dict:  # noqa: ARG001
    """Lambda handler triggered by S3 events."""
    bucket_in, key_in = receive_s3_event(event)
    logging.info(f"Bucket: {bucket_in}; Key: {key_in}")

    s3path_csv = f"s3://{bucket_in}/{key_in}"
    bucket_out = os.environ.get("OUTPUT_BUCKET", bucket_in)

    try:
        logging.info(f"Processing file: {key_in}")
        csv2pq(s3path_csv, bucket_out)
        logging.info(f"Partitioned Parquet files saved to {bucket_out}")

    except Exception as e:
        logging.exception(f"Error processing file {key_in}")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error processing file {key_in}: {e!s}"),
        }

    return {
        "statusCode": 200,
        "body": json.dumps(f"Saved partitioned Parquet for {key_in}."),
    }


def csv2pq(path_in: str, bucket_out: str) -> None:
    """Convert a S3 CSV file to S3 Parquet with DuckDB's S3 streaming.

    Partitioned by year, month, and day.
    """
    try:
        # Connect to DuckDB and process the CSV directly from S3
        con = duckdb.connect(database=":memory:")

        ext_dir = os.environ.get("DUCKDB_EXT_DIR", "")

        logging.info(f"Loading extension from {ext_dir}")

        con.execute(f"""
            SET extension_directory = '{ext_dir}';
            SET temp_directory = '/tmp';
            SET memory_limit='1GB';
        """)

        # Load the httpfs extension to allow S3 access
        con.execute("LOAD httpfs;")

        # Read the CSV from S3, and partition by year month extracted from time
        # NOTE: we do not add the day as partitioning consumes too much memory
        con.execute(f"""
            COPY (
                SELECT
                    id,
                    mag,
                    place,
                    time,
                    updated,
                    url,
                    detail,
                    felt,
                    cdi,
                    mmi,
                    alert,
                    status,
                    tsunami,
                    sig,
                    net,
                    code,
                    sources,
                    nst,
                    dmin,
                    rms,
                    gap,
                    magType,
                    type AS category,
                    title,
                    longitude,
                    latitude,
                    depth,
                    -- Extract year, month, and day from the "time" column
                    EXTRACT(YEAR FROM time)  AS year,
                    EXTRACT(MONTH FROM time) AS month,
               FROM read_csv_auto("{path_in}", header=True)
            ) TO 's3://{bucket_out}/' 
            (FORMAT 'parquet', PARTITION_BY (year, month),
             OVERWRITE_OR_IGNORE);
        """)

        logging.info(
            f"Parquet written to s3://{bucket_out}/year=.../month=...")

    except Exception:
        logging.exception("Error converting CSV to partitioned Parquet")
        raise
