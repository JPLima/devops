# What was broken, and what fixed it

Eight defects. Each one below gives the original code, the symptom it produces,
why it happens, and the change.

The unmodified originals are in [`original/`](original/), with their provenance
recorded in [`original/PROVENANCE.md`](original/PROVENANCE.md). Nothing here
was reconstructed from memory.

## Summary

| # | Defect | Symptom |
|---|---|---|
| 1 | Hardcoded S3 bucket name | `apply` fails: `BucketAlreadyExists` |
| 2 | `acl` on `aws_s3_bucket` | `validate` fails: unsupported argument |
| 3 | Lambda references an object nothing uploads | `apply` fails: key not found |
| 4 | IAM role with no permissions policy | Function runs, writes no logs, fails invisibly |
| 5 | No `source_code_hash` | Code changes are uploaded but never deployed |
| 6 | `python3.8` runtime | `apply` fails: runtime no longer accepted |
| 7 | No `required_providers` | Defect 2 becomes fatal; builds are not reproducible |
| 8 | Bucket unhardened, handler never touches S3 | Nothing proves the success criteria |

Defects 1, 2, 3 and 6 stop the apply. Defect 4 and 5 let it succeed while the
function is broken, which is worse, because there is nothing to read.

---

## 1. The bucket name is globally unique and hardcoded

```hcl
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-super-cool-bucket"
  ...
}
```

**Symptom.** `terraform apply` fails with `BucketAlreadyExists`.

**Cause.** S3 bucket names are one global namespace shared by every AWS account
on earth. `my-super-cool-bucket` was taken long before this challenge was
written, and every other candidate attempting it would collide with each other
anyway.

**Fix.** A random suffix, with the prefix exposed as a variable.

```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
  ...
}
```

`random_id` stores its value in state, so the name is generated once and stays
put across applies. It is not regenerated on every run, which would destroy and
recreate the bucket.

---

## 2. `acl` was removed from `aws_s3_bucket`

```hcl
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-super-cool-bucket"
  acl    = "private"
}
```

**Symptom.** `terraform validate` fails: `An argument named "acl" is not
expected here.`

**Cause.** Inline `acl` was deprecated in AWS provider v4 and removed from this
resource in v5. The configuration was written against v3 or v4, and because
nothing pinned the provider version (defect 7), a fresh `terraform init`
resolves v6 and the configuration stops parsing. It rotted without anyone
touching it.

**Fix.** Dropped, and not replaced with an `aws_s3_bucket_acl` resource.

ACLs are the wrong tool here. `BucketOwnerEnforced` object ownership disables
them entirely, which is stricter than a private ACL and cannot be undone by a
careless `PutObjectAcl` call:

```hcl
resource "aws_s3_bucket_ownership_controls" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
```

---

## 3. The Lambda points at an object nothing creates

```hcl
resource "aws_lambda_function" "my_lambda" {
  s3_bucket = aws_s3_bucket.my_bucket.bucket
  s3_key    = "lambda_function_payload.zip"
  ...
}
```

**Symptom.** `terraform apply` fails creating the function:
`Error occurred while GetObject. S3 Error Code: NoSuchKey.`

**Cause.** Two problems in one line. Nothing in the configuration builds or
uploads that zip, and because the key is a string literal rather than a
reference, Terraform sees no dependency between the function and the object,
so even adding an upload resource would leave the ordering to chance.

**Fix.** Build the zip during plan, upload it, and reference the object.

```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/.build/lambda_function_payload.zip"
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.my_bucket.id
  key    = "lambda_function_payload.zip"
  source = data.archive_file.lambda.output_path
  etag   = data.archive_file.lambda.output_md5
  ...
}

resource "aws_lambda_function" "my_lambda" {
  s3_bucket = aws_s3_bucket.my_bucket.bucket
  s3_key    = aws_s3_object.lambda_zip.key   # a reference, not a literal
  ...
}
```

`archive_file` is a data source, so the zip is built at plan time from source.
Nothing binary is committed and there is no manual build step. `etag` is what
tells S3 to replace the object when the zip changes; without it, a code change
uploads nothing.

Referencing `aws_s3_object.lambda_zip.key` creates the dependency the original
lacked. Terraform now knows the object must exist before the function.

Note the original also used `aws_s3_bucket_object`, which was deprecated in
provider v4 and removed in v5. `aws_s3_object` is the current name.

---

## 4. The execution role has no permissions

```hcl
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}
```

**Symptom.** The apply succeeds. The function exists. Invoking it produces an
error, and CloudWatch has no log group to explain why.

**Cause.** A trust policy says *who may assume this role*. It grants no
permissions whatsoever. The role has nothing attached, so the function cannot
even create its own log stream.

This is the most damaging defect of the eight, because it hides the others.
Every failure is silent.

**Fix.** A policy scoped to what the function actually does.

```hcl
data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "ReadWriteInvocationRecords"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.my_bucket.arn}/invocations/*"]
  }

}
```

Not `AWSLambdaBasicExecutionRole`. That managed policy grants
`logs:CreateLogGroup` on `*`, which lets the function write into any log group
in the account. This is scoped to the one group the function owns.

The log group is also created explicitly:

```hcl
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}
```

A group Lambda creates on first invocation has no retention, so logs accumulate
forever, and it cannot be named in an IAM policy because it does not exist at
plan time.

---

## 5. Code changes are uploaded but never deployed

```hcl
resource "aws_lambda_function" "my_lambda" {
  ...
  # no source_code_hash
}
```

**Symptom.** Edit `handler.py`, run `apply`. The new zip is uploaded to S3.
The deployed function keeps running the old code. The plan shows nothing to
explain it.

**Cause.** Lambda does not watch the S3 object. `source_code_hash` is how
Terraform detects that the package changed and calls `UpdateFunctionCode`.
Without it, the function resource has no attribute that differs, so there is
no diff.

This is the defect that matters most for the challenge's idempotency
requirement, in the direction people usually miss: the configuration was
*too* idempotent, ignoring a change it should have acted on.

**Fix.**

```hcl
source_code_hash = data.archive_file.lambda.output_base64sha256
```

---

## 6. The runtime reached end of support

```hcl
runtime = "python3.8"
```

**Symptom.** `terraform apply` fails:
`InvalidParameterValueException: The runtime parameter of python3.8 is no
longer supported for creating or updating AWS Lambda functions.`

**Cause.** Python 3.8 reached end of support in October 2024. AWS blocks
creating new functions on deprecated runtimes and eventually blocks updating
existing ones.

**Fix.** `python3.12`, exposed as a variable so the next bump is a one-line
change rather than a hunt through `main.tf`.

---

## 7. Nothing pinned the provider version

The original has no `terraform` block at all: no `required_version`, no
`required_providers`.

**Symptom.** The configuration works on the machine it was written on and
fails on every other one, at a different point depending on when `init` ran.

**Cause.** `terraform init` resolves the newest provider that satisfies the
constraints, and with no constraints that is whatever is current. This is the
root cause of defect 2, and of `aws_s3_bucket_object` disappearing in defect 3:
both were valid when written and were removed in v5.

**Fix.** A `versions.tf` pinning Terraform and all three providers.

**On the constraint.** The challenge forbids changing the provider settings.
The `provider "aws"` block is untouched:

```hcl
provider "aws" {
  region = "us-east-1"
}
```

Same provider, same region. `versions.tf` adds the version constraints that
were absent. Reading the constraint as forbidding that too would leave defect 2
fixable only by matching whatever provider the grader happens to resolve.

---

## 8. Nothing demonstrated the success criteria

The challenge's success criteria are:

> - Lambda function executes successfully and performs its task.
> - S3 bucket is correctly configured and accessible by the Lambda function.

The original handler:

```python
def handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }
```

**Symptom.** It returns 200 whether or not the bucket exists, whether or not
the role has permissions, whether or not anything is configured correctly. It
cannot fail, which means it cannot pass either.

**Cause.** The function never touches S3, and the bucket has no encryption, no
versioning and no public access block.

**Fix, part one: the handler does the job.** It writes a record of the
invocation and reads it back:

```python
client.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")
roundtrip = client.get_object(Bucket=bucket, Key=key)["Body"].read()
```

A successful put only proves write access. Reading it back proves the object
landed where we think it did and that the role can decrypt it. Errors are
logged with the S3 error code and re-raised, so a failure appears in CloudWatch
as a reason rather than as a 200.

The bucket name comes from an environment variable Terraform sets, read at call
time rather than at import, so a missing variable surfaces as a `RuntimeError`
naming it instead of an opaque `Runtime.ImportModuleError`.

**Fix, part two: the bucket is configured.** Versioning, SSE-S3 encryption,
public access blocked, ACLs disabled, a bucket policy denying non-TLS requests,
and a lifecycle rule expiring invocation records after 90 days.

**Fix, part three: it is tested.** Eight tests in `tests/`, running against
moto, cover the round trip, the key layout, the failure modes and the client
caching. Run them with `pytest tests -v`.

---

## Changes that were not defects

Additions that no symptom forced, listed separately so the eight above stay
honest:

- **`timeout = 30` and `memory_size = 256`.** The Lambda defaults are 3 seconds
  and 128 MB, which is tight for two S3 round trips on a cold start.
- **`reserved_concurrent_executions = 10`.** Without a reserved limit, a
  runaway trigger consumes the account's whole concurrency pool.
- **`force_destroy = true` on the bucket.** So `terraform destroy` works
  without a manual empty step. Correct for a challenge, wrong for production.
- **An explicit CloudWatch log group.** Lambda already wrote to CloudWatch
  Logs, or would have if the role had let it, so this is not a new service.
  It is here because a group Lambda creates on first invocation has no
  retention and cannot be named in an IAM policy at plan time.

## What was deliberately not added

The constraint is "limited to the current AWS services and can't introduce a
new service". The original used three: S3, Lambda and IAM.

**No KMS.** The bucket uses SSE-S3 (`AES256`) rather than a customer-managed
key. A CMK would be better security, and it is what Tasks 1 and 2 do, but the
original configuration had no encryption block at all, so KMS would be a new
service here. Two checkov findings are suppressed for this reason, each with
the constraint cited inline:

| Check | What it wants |
|---|---|
| `CKV_AWS_145` | S3 encrypted with SSE-KMS rather than SSE-S3 |
| `CKV_AWS_158` | The CloudWatch log group encrypted with a CMK |
| `CKV_AWS_173` | Lambda environment variables encrypted with a CMK |

Lambda already encrypts environment variables at rest with an AWS-managed key,
so the third is about auditability rather than about the data being exposed.

**No dead letter queue** (`CKV_AWS_116`). A DLQ needs SQS or SNS. The function
is also invoked synchronously, where a DLQ does not apply because the caller
receives the error.

Both would be the right call the day the constraint is lifted.

## Constraints respected

| Constraint | How |
|---|---|
| Cannot change the Terraform provider settings | The `provider "aws"` block is byte-for-byte unchanged, region included. See defect 7 on `versions.tf`. |
| Limited to the current AWS services, no new ones | S3, Lambda and IAM, the three the original used, plus the CloudWatch log group the function already wrote to. No KMS: see below. |
| All changes implemented via code | Every change is in `terraform/` or `lambda/`. No console steps, no manual uploads. |

## Verification

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
pytest tests -v
```

Against a real account:

```bash
terraform -chdir=terraform apply
terraform -chdir=terraform output -raw invoke_command | sh
terraform -chdir=terraform output -raw verify_object_command | sh
```

The first prints the handler's response, including `"roundtrip_ok": true`. The
second lists the object it wrote, which is the bucket being accessible from the
function, demonstrated rather than asserted.
