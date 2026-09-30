# Task 3: Lambda and Terraform troubleshooting

A broken Terraform and Lambda project, diagnosed and fixed.

**[FIXES.md](FIXES.md) is the deliverable.** Eight defects, each with the
original code, the symptom, the cause and the change.

## Layout

```
task3-lambda-troubleshooting/
├── FIXES.md          what was broken and what fixed it
├── original/         the unmodified broken files, with provenance
├── terraform/        the fixed configuration
├── lambda/           the fixed handler
└── tests/            eight tests, against moto
```

## Where the original came from

The repository the challenge links to,
`github.com/spinbet/devops-aws-lambda-troubleshooting-files`, no longer
resolves. A public copy preserves the original upload as its first commit,
`e17c075`, before that author's own fixes landed. Those files are in
[`original/`](original/) untouched, and
[`original/PROVENANCE.md`](original/PROVENANCE.md) records exactly how to
verify that. Nothing was reconstructed from memory.

The challenge document also shows a `terraform/` and `lambda/` tree; the actual
repository is flat. The layout above follows the document.

## The eight defects

| # | Defect | Symptom |
|---|---|---|
| 1 | Hardcoded S3 bucket name | `apply` fails: `BucketAlreadyExists` |
| 2 | `acl` on `aws_s3_bucket` | `validate` fails: unsupported argument |
| 3 | Lambda references an object nothing uploads | `apply` fails: key not found |
| 4 | IAM role with no permissions policy | Runs, writes no logs, fails invisibly |
| 5 | No `source_code_hash` | Code changes uploaded but never deployed |
| 6 | `python3.8` runtime | `apply` fails: runtime no longer accepted |
| 7 | No `required_providers` | Defect 2 becomes fatal; builds not reproducible |
| 8 | Bucket unhardened, handler never touches S3 | Nothing proves the success criteria |

Defects 1, 2, 3 and 6 stop the apply, so they announce themselves. Defect 4 is
the dangerous one: the apply succeeds, the function exists, and every failure
after that is silent because the role cannot write logs.

## Running it

### Tests, no AWS account needed

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r tests/requirements.txt
pytest tests -v
```

Eight tests against [moto](https://github.com/getmoto/moto), which implements
the S3 API in-process.

### Static checks

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

### Against a real account

The provider is pinned to `us-east-1` and stays that way; the challenge
forbids changing provider settings.

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

Then prove the two success criteria:

```bash
terraform -chdir=terraform output -raw invoke_command | sh
terraform -chdir=terraform output -raw verify_object_command | sh
```

The first invokes the function and prints its response, which includes
`"roundtrip_ok": true`. The second lists the object it wrote. That is the
bucket being accessible from the function, demonstrated rather than asserted.

To confirm idempotency, apply twice:

```bash
terraform -chdir=terraform apply
terraform -chdir=terraform plan   # No changes. Your infrastructure matches the configuration.
```

## What the handler does

It writes a JSON record of the invocation to
`invocations/YYYY/MM/DD/<uuid>.json` and reads it straight back.

The read back is the point. A successful `PutObject` proves write access;
reading proves the object landed where we think it did and that the role can
decrypt it. Errors are logged with the S3 error code and re-raised, so a
failure shows up in CloudWatch as a reason rather than as a 200.

The original returned `Hello from Lambda!` unconditionally, which cannot fail
and therefore cannot pass either.

## Constraints

| Constraint | How it is respected |
|---|---|
| Cannot change the Terraform provider settings | The `provider "aws"` block is byte-for-byte unchanged, region included. `versions.tf` adds the `required_providers` constraints that were missing; see defect 7 in FIXES.md for the reasoning. |
| Limited to the current AWS services | S3, Lambda, IAM, CloudWatch Logs and KMS. KMS was already in use by the bucket's encryption. |
| All changes implemented via code | Everything is in `terraform/` or `lambda/`. No console steps, no manual uploads, no binary committed. |
