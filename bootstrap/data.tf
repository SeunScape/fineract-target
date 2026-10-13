data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id        = data.aws_caller_identity.current.account_id
  state_bucket_name = "fineract-target-tfstate-${local.account_id}"
  target_state_key  = "target/terraform.tfstate"
  # GitHub immutable OIDC subject: owner@<owner id>/repo@<repo id>
  github_repo_path = "${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
}
