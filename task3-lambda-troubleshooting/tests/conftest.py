"""Fixtures for the handler tests."""

import importlib
import os
import sys
from pathlib import Path

import pytest

LAMBDA_DIR = Path(__file__).resolve().parent.parent / "lambda"
sys.path.insert(0, str(LAMBDA_DIR))


@pytest.fixture(autouse=True)
def fake_credentials(monkeypatch):
    """Stop boto3 finding real credentials and reaching a live account."""
    for name in (
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SECURITY_TOKEN",
        "AWS_SESSION_TOKEN",
    ):
        monkeypatch.setenv(name, "testing")

    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.delenv("AWS_PROFILE", raising=False)


@pytest.fixture
def handler_module():
    """A fresh handler with its cached client cleared between tests."""
    import handler

    importlib.reload(handler)
    handler._S3 = None

    yield handler

    handler._S3 = None


class FakeContext:

    aws_request_id = "11111111-2222-3333-4444-555555555555"
    function_name = "my_lambda"
    memory_limit_in_mb = 256


@pytest.fixture
def context():
    return FakeContext()
