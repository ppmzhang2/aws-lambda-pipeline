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

    Process and save chunk-by-chunk to avoid memory exhaustion.
    """
    ext_dir = os.environ.get("DUCKDB_EXT_DIR", "")

    con = duckdb.connect(database=":memory:")

    logging.info("Configuring Database")
    con.execute(f"""
        SET extension_directory = '{ext_dir}';
        SET temp_directory = '/tmp';
        SET memory_limit='2GB';
    """)
    con.execute("LOAD httpfs;")

    logging.info(f"Loading CSV from {path_in}")
    con.execute(f"""
        CREATE TABLE csv_table AS
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
            mag_type,
            category,
            title,
            longitude,
            latitude,
            depth,
            EXTRACT(YEAR FROM time)  AS year,
            EXTRACT(MONTH FROM time) AS month,
            EXTRACT(DAY FROM time)   AS day
       FROM read_csv_auto("{path_in}", header=True)
    """)

    # Get unique days to process
    seq_ymd = con.execute("""
        SELECT year, month, day
          FROM csv_table
         GROUP BY 1, 2, 3
    """).fetchall()

    logging.info(f"Found {len(seq_ymd)} unique year-month-day records.")

    # Process each day separately
    for year, month, day in seq_ymd:
        logging.info(f"Processing year={year}, month={month}, day={day}")

        # Filter data for this specific day
        con.execute(
            f"""
            COPY (
              SELECT *
                FROM csv_table
               WHERE year = ? AND month = ? AND day = ?
            ) TO 's3://{bucket_out}/'
            (FORMAT 'parquet', PARTITION_BY (year, month, day),
             OVERWRITE_OR_IGNORE);
            """,  # noqa: S608
            [year, month, day],
        )

        logging.info(
            f"Parquet files for year={year}, month={month}, day={day} saved.")
