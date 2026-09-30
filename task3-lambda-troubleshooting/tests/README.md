# Tests

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r tests/requirements.txt
pytest tests -v
```

They run against [moto](https://github.com/getmoto/moto), which implements the
S3 API in-process. No AWS account, no credentials, no cost.

What they prove: the handler writes an object, reads it back, namespaces its
keys under the prefix the IAM policy grants, and fails loudly rather than
returning 200 when the bucket or the permissions are wrong.

What they do not prove: that the IAM policy in `terraform/main.tf` is
sufficient. Moto does not evaluate IAM. That part is reviewed by hand in
`FIXES.md`, statement by statement.
