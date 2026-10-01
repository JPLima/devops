"""Handler tests, against moto.

These cover the handler's logic and error handling. They do not prove the IAM
policy in terraform/main.tf is sufficient; moto does not evaluate IAM.
"""

import json
import os

import boto3
import pytest
from botocore.exceptions import ClientError
from moto import mock_aws

BUCKET = "test-bucket"


@pytest.fixture
def bucket(monkeypatch):
    """An empty S3 bucket, with the handler pointed at it."""
    with mock_aws():
        client = boto3.client("s3", region_name="us-east-1")
        client.create_bucket(Bucket=BUCKET)
        monkeypatch.setenv("DATA_BUCKET", BUCKET)
        yield client


def test_writes_an_object_and_reads_it_back(bucket, handler_module, context):
    response = handler_module.handler({"source": "test"}, context)

    assert response["statusCode"] == 200

    body = json.loads(response["body"])
    assert body["roundtrip_ok"] is True
    assert body["bytes_written"] == body["bytes_read"]
    assert body["bucket"] == BUCKET

    # The object is really there, not just reported as written.
    stored = bucket.get_object(Bucket=BUCKET, Key=body["key"])["Body"].read()
    assert json.loads(stored)["event"] == {"source": "test"}


def test_object_key_is_namespaced_and_dated(bucket, handler_module, context):
    """The IAM policy grants PutObject on invocations/* only, so the key
    layout is part of the contract."""
    response = handler_module.handler({}, context)
    key = json.loads(response["body"])["key"]

    assert key.startswith("invocations/")

    prefix, year, month, day, filename = key.split("/")
    assert len(year) == 4 and year.isdigit()
    assert len(month) == 2 and month.isdigit()
    assert len(day) == 2 and day.isdigit()
    assert filename.endswith(".json")


def test_record_carries_the_invocation_context(bucket, handler_module, context):
    """The stored record identifies which invocation wrote it."""
    response = handler_module.handler({"hello": "world"}, context)
    key = json.loads(response["body"])["key"]

    stored = json.loads(bucket.get_object(Bucket=BUCKET, Key=key)["Body"].read())

    assert stored["request_id"] == context.aws_request_id
    assert stored["function_name"] == context.function_name
    assert stored["timestamp"].endswith("+00:00")


def test_two_invocations_do_not_overwrite_each_other(bucket, handler_module, context):
    """A fixed key would quietly keep only the last record."""
    first = json.loads(handler_module.handler({}, context)["body"])["key"]
    second = json.loads(handler_module.handler({}, context)["body"])["key"]

    assert first != second

    listed = bucket.list_objects_v2(Bucket=BUCKET, Prefix="invocations/")
    assert listed["KeyCount"] == 2


def test_missing_environment_variable_fails_with_a_readable_message(
    handler_module, context, monkeypatch
):
    """Reading at call time means this is a RuntimeError naming the variable."""
    monkeypatch.delenv("DATA_BUCKET", raising=False)

    with pytest.raises(RuntimeError, match="DATA_BUCKET"):
        handler_module.handler({}, context)


def test_empty_environment_variable_is_treated_as_missing(
    handler_module, context, monkeypatch
):
    monkeypatch.setenv("DATA_BUCKET", "")

    with pytest.raises(RuntimeError, match="DATA_BUCKET"):
        handler_module.handler({}, context)


def test_a_missing_bucket_raises_instead_of_returning_200(
    handler_module, context, monkeypatch
):
    """The original returned 200 unconditionally, so a broken bucket looked
    like success."""
    with mock_aws():
        monkeypatch.setenv("DATA_BUCKET", "bucket-that-does-not-exist")

        with pytest.raises(ClientError) as raised:
            handler_module.handler({}, context)

        assert raised.value.response["Error"]["Code"] in {
            "NoSuchBucket",
            "404",
        }


def test_client_is_built_once_and_reused(bucket, handler_module, context):
    """The cached client survives between invocations."""
    assert handler_module._S3 is None

    handler_module.handler({}, context)
    first = handler_module._S3

    handler_module.handler({}, context)

    assert handler_module._S3 is first
