output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "kms_alias" {
  value = aws_kms_alias.main.name
}

output "gha_plan_role_arn" {
  value = aws_iam_role.gha_plan.arn
}

output "gha_apply_role_arn" {
  value = aws_iam_role.gha_apply.arn
}
