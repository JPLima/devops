output "s3_bucket_name" {
  description = "Data bucket the function writes to."
  value       = aws_s3_bucket.my_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the data bucket."
  value       = aws_s3_bucket.my_bucket.arn
}

output "lambda_function_name" {
  description = "Name of the function."
  value       = aws_lambda_function.my_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the function."
  value       = aws_lambda_function.my_lambda.arn
}

output "lambda_role_arn" {
  description = "ARN of the execution role."
  value       = aws_iam_role.iam_for_lambda.arn
}

output "log_group_name" {
  description = "CloudWatch log group the function writes to."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "kms_key_arn" {
  description = "Key encrypting the bucket and the function environment."
  value       = module.bucket_key.arn
}

output "invoke_command" {
  description = "Invokes the function and prints the response."
  value       = "aws lambda invoke --region ${data.aws_region.current.region} --function-name ${aws_lambda_function.my_lambda.function_name} --payload '{}' --cli-binary-format raw-in-base64-out /dev/stdout"
}

output "verify_object_command" {
  description = "Lists the objects the function has written."
  value       = "aws s3 ls s3://${aws_s3_bucket.my_bucket.bucket}/invocations/ --recursive"
}
