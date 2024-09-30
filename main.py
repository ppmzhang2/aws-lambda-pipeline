"""Fetch earthquake data from the USGS API and upload it to an S3 bucket."""

import asyncio
from collections import namedtuple
from collections.abc import Generator
import csv
import datetime
import io
import json
from math import floor

import aiohttp
from aws_lambda_typing.context import Context
import boto3

_BASE_URL = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson"
RATE_LIMIT = 5  # Maximum number of requests per second
REQUEST_TIMEOUT = 2  # Timeout between requests in seconds

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
        "magType",
        "type",
        "title",
        "longitude",
        "latitude",
        "depth",
    ],
)


def _date_range_gen(
    start_date: datetime.date,
    end_date: datetime.date,
    days: int,
) -> Generator[tuple[datetime.date, datetime.date], None, None]:
    delta = datetime.timedelta(days=days)
    n = floor((end_date - start_date) / delta)
    for i in range(n):
        yield start_date + delta * i, start_date + delta * (i + 1)
    yield start_date + delta * n, end_date


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
        magType=dc["properties"]["magType"],
        type=dc["properties"]["type"],
        title=dc["properties"]["title"],
        longitude=dc["geometry"]["coordinates"][0],
        latitude=dc["geometry"]["coordinates"][1],
        depth=dc["geometry"]["coordinates"][2],
    )


async def fetch_features(
    start_date: datetime.date,
    end_date: datetime.date,
    semaphore: asyncio.Semaphore,
) -> list[Feature]:
    """One fetch request to the USGS API."""
    start_dt_str = _date_str(start_date)
    end_dt_str = _date_str(end_date)
    url = _BASE_URL + f"&starttime={start_dt_str}&endtime={end_dt_str}"

    async with (
            semaphore,
            aiohttp.ClientSession() as client,
            client.get(url) as resp,
    ):
        resp.raise_for_status()
        seq = (await resp.json())["features"]
        await asyncio.sleep(REQUEST_TIMEOUT)  # Rate limiting delay
    return [_parse_feature(dc) for dc in seq]


async def all_features(
    start_date: datetime.date,
    end_date: datetime.date,
    days: int = 10,
    rate_limit: int = RATE_LIMIT,
) -> list[Feature]:
    """Fetch all features in the date range."""
    semaphore = asyncio.Semaphore(rate_limit)
    seq_range = _date_range_gen(start_date, end_date, days)

    coroutines = [
        fetch_features(start, end, semaphore) for start, end in seq_range
    ]

    seq = await asyncio.gather(*coroutines)
    return [item for sublist in seq for item in sublist]


def convert_to_csv(features: list[Feature]) -> str:
    """Convert the features list to a CSV format."""
    output = io.StringIO()
    csv_writer = csv.writer(output)

    # Write CSV header
    csv_writer.writerow(Feature._fields)

    # Write each feature to the CSV
    for feature in features:
        csv_writer.writerow(feature)

    return output.getvalue()


def upload_to_s3(bucket_name: str, key: str, csv_data: str) -> None:
    """Upload the CSV data to the specified S3 bucket."""
    s3 = boto3.client("s3")
    s3.put_object(Bucket=bucket_name, Key=key, Body=csv_data)


# Lambda handler function
def handler(event: dict, context: Context) -> dict:  # noqa: ARG001
    """Lambda handler function to fetch earthquake data and upload it to S3."""
    # Extract parameters from event
    dt_beg = datetime.date.fromisoformat(event.get("start_date", "2020-01-01"))
    dt_end = datetime.date.fromisoformat(event.get("end_date", "2020-01-10"))
    bucket_name = event.get("bucket_name")
    file_key = event.get("file_key", f"earthquake_data_{dt_beg}_{dt_end}.csv")

    # Fetch the earthquake data
    features = asyncio.run(all_features(dt_beg, dt_end))

    # Convert the features list to CSV format
    csv_data = convert_to_csv(features)

    # Upload the CSV file to S3
    upload_to_s3(bucket_name, file_key, csv_data)

    return {
        "statusCode":
        200,
        "body":
        json.dumps({
            "message":
            f"CSV file successfully uploaded to s3://{bucket_name}/{file_key}",
            "total_records": len(features),
        }),
    }
