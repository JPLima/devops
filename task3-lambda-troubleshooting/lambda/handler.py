"""Lambda entry point.

The original handler returned a greeting and never touched S3, so nothing in
the project demonstrated the success criterion that the bucket is correctly
configured and accessible to the function.

This one writes an object and reads it back. If the bucket is missing, the key
policy is wrong, or the role lacks kms:Decrypt, the invocation fails loudly
with the reason instead of returning 200 while proving nothing.
"""

import datetime
import json
import os
import uuid

import boto3
from botocore.exceptions import ClientError

# Cached across invocations, but built on first use rather than at import.
#
# Lambda keeps the execution environment warm between calls, so a client per
# invocation would pay the TLS handshake every time for nothing. Building it at
# import time instead would freeze the credentials and endpoint before the
# module is usable, which also makes the function untestable: a test harness
# cannot intercept a client that already exists.
_S3 = None


def _s3():
    global _S3
    if _S3 is None:
        _S3 = boto3.client("s3")
    return _S3


def _bucket_name():
    """Read the bucket from the environment.

    Deliberately not a module-level constant: a missing variable should fail
    the invocation with a clear message, not the import, which surfaces as an
    opaque Runtime.ImportModuleError.
    """
    bucket = os.environ.get("DATA_BUCKET")
    if not bucket:
        raise RuntimeError(
            "DATA_BUCKET is not set. Terraform sets it in the function's "
            "environment block."
        )
    return bucket


def handler(event, context):
    """Write a record of this invocation to S3 and read it back."""
    bucket = _bucket_name()

    now = datetime.datetime.now(datetime.timezone.utc)
    key = f"invocations/{now:%Y/%m/%d}/{uuid.uuid4()}.json"

    record = {
        "request_id": getattr(context, "aws_request_id", None),
        "function_name": getattr(context, "function_name", None),
        "timestamp": now.isoformat(),
        "event": event,
    }

    body = json.dumps(record).encode("utf-8")

    try:
        client = _s3()

        client.put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType="application/json",
        )

        # The read back is the point. A successful put only proves write
        # access; reading proves the object landed where we think it did and
        # that the role can decrypt it.
        roundtrip = client.get_object(Bucket=bucket, Key=key)["Body"].read()

    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "Unknown")
        message = error.response.get("Error", {}).get("Message", str(error))

        # Logged rather than swallowed: this is what shows up in CloudWatch,
        # and it is the difference between "the lambda is broken" and
        # "the role is missing kms:Decrypt".
        print(f"S3 {code} on s3://{bucket}/{key}: {message}")
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
