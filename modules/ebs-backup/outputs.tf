output "dlm_policy_arn" {
  description = "ARN of the shared EBS snapshot lifecycle policy."
  value       = aws_dlm_lifecycle_policy.snapshots.arn
}
