output "guardrail_id" {
  description = "Guardrail ID to pass in every request."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_version" {
  description = "Guardrail version enforced by IAM."
  value       = aws_bedrock_guardrail_version.this.version
}

output "permission_set_arn" {
  description = "ARN of the BedrockUser permission set."
  value       = aws_ssoadmin_permission_set.bedrock_user.arn
}

output "log_bucket" {
  description = "S3 bucket holding invocation logs."
  value       = aws_s3_bucket.logs.id
}

output "log_group" {
  description = "CloudWatch log group for invocation logs."
  value       = aws_cloudwatch_log_group.invocations.name
}
