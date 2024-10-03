"""Read a CSV file from S3, convert it to Parquet, and save it back to S3."""

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
    bucket_out = os.environ.get("OUTPUT_BUCKET", bucket_in)
    key_out = f"{os.path.basename(key_in).replace('.csv', '.parquet')}"
    s3path_csv = f"s3://{bucket_in}/{key_in}"
    s3path_pq = f"s3://{bucket_out}/{key_out}"

    logging.info(f"Bucket: {bucket_in}; Key: {key_in}")

    try:
        logging.info(f"Processing file: {key_in}")
        csv2pq(s3path_csv, s3path_pq)
        logging.info(f"Parquet file saved to {s3path_pq}")

    except Exception as e:
        logging.exception(f"Error processing file {key_in}")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error processing file {key_in}: {e!s}"),
        }

    return {
        "statusCode": 200,
        "body": json.dumps(f"Saved Parquet for {key_in}."),
    }


def csv2pq(path_in: str, path_out: str) -> None:
    """Convert a S3 CSV file to S3 Parquet with DuckDB's S3 streaming."""
    try:
        # Connect to DuckDB and process the CSV directly from S3
        con = duckdb.connect(database=":memory:")

        # Load the httpfs extension to allow S3 access
        con.execute("LOAD httpfs;")

        # Streaming: DuckDB reads the CSV directly from S3 and writes the
        # Parquet directly back to S3
        con.execute(f"""
            COPY (
                SELECT
                    id,
                    mag,
                    place,
                    TIMESTAMP 'epoch' +
                        time / 1000 * INTERVAL '1 second' AS time,
                    TIMESTAMP 'epoch' +
                        updated / 1000 * INTERVAL '1 second' AS updated,
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
                    depth
               FROM read_csv_auto("{path_in}", header=True)
            ) TO "{path_out}" (FORMAT 'parquet');
        """)

        logging.info(f"Parquet written to {path_out}")

    except Exception:
        logging.exception("Error converting CSV to Parquet")
        raise
