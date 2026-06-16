output "rule_arn" {
  description = "ARN of the EventBridge rule that forwards Security Hub findings to the central bus."
  value       = aws_cloudwatch_event_rule.forward.arn
}

output "rule_name" {
  description = "Name of the forwarding rule (useful for CloudWatch AWS/Events metrics)."
  value       = aws_cloudwatch_event_rule.forward.name
}

output "role_arn" {
  description = "ARN of the IAM role EventBridge assumes to PutEvents on the central bus."
  value       = aws_iam_role.forward.arn
}

output "dlq_arn" {
  description = "ARN of the forwarding DLQ, or null when enable_dlq is false."
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}

output "dlq_url" {
  description = "URL of the forwarding DLQ, or null when enable_dlq is false."
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].id : null
}
