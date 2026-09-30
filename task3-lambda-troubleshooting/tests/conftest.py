"""Test fixtures for the Lambda handler.

The handler lives in ../lambda, which is not a package and is not on the path
when pytest runs from the repository root, so it is added here.
"""

import importlib
import os
import sys
from pathlib import Path

import pytest

LAMBDA_DIR = Path(__file__).resolve().parent.parent / "lambda"
sys.path.insert(0, str(LAMBDA_DIR))


@pytest.fixture(autouse=True)
def fake_credentials(monkeypatch):
    """Stop boto3 finding real credentials.

    Without this, a developer with a live AWS profile would have moto's
    interception bypassed for anything it does not cover, and a test could
    reach a real account.
    """
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
    """A freshly imported handler with its cached S3 client cleared.

    The handler caches its client in a module global, which is correct for a
    warm Lambda environment and wrong for a test suite: without the reset, the
    second test would reuse a client bound to the first test's mock.
    """
    import handler

    importlib.reload(handler)
    handler._S3 = None

    yield handler

    handler._S3 = None


class FakeContext:
    """Stand-in for the Lambda context object."""

    aws_request_id = "11111111-2222-3333-4444-555555555555"
    function_name = "my_lambda"
    memory_limit_in_mb = 256


@pytest.fixture
def context():
    return FakeContext()
