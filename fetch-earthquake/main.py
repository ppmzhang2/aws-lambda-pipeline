"""Fetch earthquake data from the USGS API and upload it to an S3 bucket."""

import asyncio
from collections import namedtuple
from collections.abc import Generator
import csv
import datetime
import io
import json
import logging
import math
import os

import aiohttp
from aws_lambda_typing.context import Context
import boto3

BASE_URL = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson"
RATE_LIMIT = 5  # Maximum number of requests per second
REQUEST_TIMEOUT = 2  # Timeout between requests in seconds
N_DAY = 10  # Number of days to fetch data in each batch

# Set up basic logging configuration
logging.basicConfig(level=logging.INFO)

Feature = namedtuple(
    "Feature",
    [
        "id",
        "mag",
        "place",
        "time",
        "updated",
        "tz",
        "url",
        "detail",
        "felt",
        "cdi",
        "mmi",
        "alert",
        "status",
        "tsunami",
        "sig",
        "net",
        "code",
        "ids",
        "sources",
        "types",
        "nst",
        "dmin",
        "rms",
        "gap",
        "mag_type",
        "category",
        "title",
        "longitude",
        "latitude",
        "depth",
    ],
)


def dt_tuple_gen(
    start_date: datetime.date,
    end_date: datetime.date,
    days: int,
) -> Generator[tuple[datetime.date, datetime.date], None, None]:
    """Generate date tuples with a given interval."""
    delta = datetime.timedelta(days=days)
    n = math.floor((end_date - start_date) / delta)
    for i in range(n):
        car = start_date + delta * i
        cdr = start_date + delta * (i + 1)
        yield car, cdr

    # whether yield the last tuple or not
    if cdr < end_date:
        yield cdr, end_date


def _date_str(dt: datetime.date) -> str:
    """Format the date object as "yyyy-mm-dd" string.

    Args:
        dt (date): Date object to format

    Returns:
        str: "yyyy-mm-dd" formatted string
    """
    return dt.strftime("%Y-%m-%d")


def _parse_feature(dc: dict) -> Feature:
    return Feature(
        id=dc["id"],
        mag=dc["properties"]["mag"],
        place=dc["properties"]["place"],
        time=datetime.datetime.fromtimestamp(
            dc["properties"]["time"] / 1e3,
            tz=datetime.UTC,
        ),
        updated=datetime.datetime.fromtimestamp(
            dc["properties"]["updated"] / 1e3,
            tz=datetime.UTC,
        ),
        tz=dc["properties"]["tz"],
        url=dc["properties"]["url"],
        detail=dc["properties"]["detail"],
        felt=dc["properties"]["felt"],
        cdi=dc["properties"]["cdi"],
        mmi=dc["properties"]["mmi"],
        alert=dc["properties"]["alert"],
        status=dc["properties"]["status"],
        tsunami=dc["properties"]["tsunami"],
        sig=dc["properties"]["sig"],
        net=dc["properties"]["net"],
        code=dc["properties"]["code"],
        ids=dc["properties"]["ids"],
        sources=dc["properties"]["sources"],
        types=dc["properties"]["types"],
        nst=dc["properties"]["nst"],
        dmin=dc["properties"]["dmin"],
        rms=dc["properties"]["rms"],
        gap=dc["properties"]["gap"],
        mag_type=dc["properties"]["magType"],
        category=dc["properties"]["type"],
        title=dc["properties"]["title"],
        longitude=dc["geometry"]["coordinates"][0],
        latitude=dc["geometry"]["coordinates"][1],
        depth=dc["geometry"]["coordinates"][2],
    )


def feat2csv(features: list[Feature]) -> str:
    """Convert the features list to a CSV format."""
    output = io.StringIO()
    csv_writer = csv.writer(output)

    # Write CSV header
    csv_writer.writerow(Feature._fields)

    # Write each feature to the CSV
    for feature in features:
        csv_writer.writerow(feature)

    return output.getvalue()


def upload_to_s3(bucket: str, key: str, csv_data: str) -> None:
    """Upload the CSV data to the specified S3 bucket."""
    s3 = boto3.client("s3")
    s3.put_object(Bucket=bucket, Key=key, Body=csv_data)


async def fetch_save(
    date_beg: datetime.date,
    date_end: datetime.date,
    sem: asyncio.Semaphore,
    bucket: str,
    base_key: str,
) -> None:
    """Fetch features for a given date range and upload the result to S3."""
    dt_beg_str = _date_str(date_beg)
    dt_end_str = _date_str(date_end)
    url = BASE_URL + f"&starttime={dt_beg_str}&endtime={dt_end_str}"

    async with (
            sem,
            aiohttp.ClientSession() as client,
            client.get(url) as resp,
    ):
        resp.raise_for_status()
        seq = (await resp.json())["features"]
        await asyncio.sleep(REQUEST_TIMEOUT)  # Rate limiting delay

    features = [_parse_feature(dc) for dc in seq]

    # Convert features to CSV
    csv_data = feat2csv(features)

    # Generate unique file key for this batch
    file_key = f"{base_key}_{dt_beg_str}_{dt_end_str}.csv"

    # Upload CSV data to S3
    upload_to_s3(bucket, file_key, csv_data)

    logging.info(f"Uploaded CSV data to S3: {file_key}")


async def fetch_save_all(
    start_date: datetime.date,
    end_date: datetime.date,
    bucket: str,
    base_key: str,
) -> None:
    """Fetch and upload all features in range by dividing into coroutines."""
    sem = asyncio.Semaphore(RATE_LIMIT)
    seq_range = dt_tuple_gen(start_date, end_date, N_DAY)

    coroutines = [
        fetch_save(start, end, sem, bucket, base_key)
        for start, end in seq_range
    ]

    await asyncio.gather(*coroutines)


def handler(event: dict, context: Context) -> dict:  # noqa: ARG001
    """Lambda handler function to fetch earthquake data and upload it to S3."""
    logging.info(f"Processing event: {json.dumps(event)}")

    try:
        bucket_id = os.environ["BUCKET_NAME"]
        # Extract parameters from event
        dt_beg_str = event.get("start_date", "2020-01-01")
        dt_end_str = event.get("end_date", "2020-01-10")
        dt_beg = datetime.date.fromisoformat(dt_beg_str)
        dt_end = datetime.date.fromisoformat(dt_end_str)
        base_key = f"eq_raw_{dt_beg_str}_{dt_end_str}"
        # Fetch and upload earthquake data for each date range
        asyncio.run(fetch_save_all(dt_beg, dt_end, bucket_id, base_key))

    except Exception as e:
        logging.exception("An error occurred")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
        }
    else:
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "CSV file successfully uploaded"}),
        }
