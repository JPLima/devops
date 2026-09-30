output "state_bucket" {
  description = "Bucket name to put in the backend block."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table name to put in the backend block."
  value       = aws_dynamodb_table.locks.name
}

output "kms_key_arn" {
  description = "KMS key encrypting state and lock entries."
  value       = aws_kms_key.state.arn
}

output "backend_block" {
  description = "Ready to paste backend configuration for the root module."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket               = "${aws_s3_bucket.state.id}"
        key                  = "task1/terraform.tfstate"
        workspace_key_prefix = "env"
        region               = "${var.region}"
        dynamodb_table       = "${aws_dynamodb_table.locks.name}"
        encrypt              = true
      }
    }
  EOT
}
