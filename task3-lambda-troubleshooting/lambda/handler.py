"""Writes a record of each invocation to S3 and reads it back.

The read back is the point: a successful put only proves write access, where
reading proves the object landed where we think it did and that the role can
decrypt it.
"""

import datetime
import json
import os
import uuid

import boto3
from botocore.exceptions import ClientError

# Built on first use, not at import, so the execution environment can be warm
# across invocations and a test can intercept the client.
_S3 = None


def _s3():
    global _S3
    if _S3 is None:
        _S3 = boto3.client("s3")
    return _S3


def _bucket_name():
    # Read at call time, not import, so a missing variable surfaces as this
    # error rather than Runtime.ImportModuleError.
    bucket = os.environ.get("DATA_BUCKET")
    if not bucket:
        raise RuntimeError("DATA_BUCKET is not set. Terraform sets it on the function.")
    return bucket


def handler(event, context):
    bucket = _bucket_name()

    now = datetime.datetime.now(datetime.timezone.utc)
    key = f"invocations/{now:%Y/%m/%d}/{uuid.uuid4()}.json"

    body = json.dumps(
        {
            "request_id": getattr(context, "aws_request_id", None),
            "function_name": getattr(context, "function_name", None),
            "timestamp": now.isoformat(),
            "event": event,
        }
    ).encode("utf-8")

    try:
        client = _s3()
        client.put_object(
            Bucket=bucket, Key=key, Body=body, ContentType="application/json"
        )
        roundtrip = client.get_object(Bucket=bucket, Key=key)["Body"].read()
    except ClientError as error:
        err = error.response.get("Error", {})
        # Logged before re-raising: this is what distinguishes a broken bucket
        # from a role missing kms:Decrypt.
        print(
            f"S3 {err.get('Code', 'Unknown')} on s3://{bucket}/{key}: "
            f"{err.get('Message', error)}"
        )
        raise

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "message": "Wrote and read back an object",
                "bucket": bucket,
                "key": key,
                "bytes_written": len(body),
                "bytes_read": len(roundtrip),
                "roundtrip_ok": roundtrip == body,
            }
        ),
    }
