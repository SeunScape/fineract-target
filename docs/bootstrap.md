# Bootstrap layer: record of the manual apply

`bootstrap/` is the only Terraform in this repo applied by a person rather than the pipeline. It creates
what the pipeline needs to exist: the state bucket, the KMS key, the GitHub OIDC provider and the two
pipeline roles. This file records exactly how it was applied.

## Applied

| | |
|---|---|
| Date | 2026-10-12 |
| Applied by | Repo owner, from a laptop, using the `default` AWS CLI profile (admin) |
| Account / region | `755431180020` / `eu-west-2` |
| Terraform | v1.16.1 (`required_version = "~> 1.16.0"`) |
| AWS provider | `hashicorp/aws` 6.68.0 (pinned exactly, lock file committed) |
| Commit | `b5da85b` |

## Resources created (16)

| Resource | Name / detail |
|---|---|
| KMS key | Customer managed, rotation enabled, 30-day deletion window |
| KMS alias | `alias/fineract-target` |
| S3 bucket | `fineract-target-tfstate-755431180020`, with ownership controls `BucketOwnerEnforced` |
| Bucket versioning | Enabled |
| Bucket encryption | SSE-KMS with the key above, S3 bucket key on |
| Public access block | All four settings `true` |
| Bucket policy | Denies any request where `aws:SecureTransport = false` |
| OIDC provider | `token.actions.githubusercontent.com`, audience `sts.amazonaws.com` |
| IAM role `gha-plan` | Trust: `aud = sts.amazonaws.com`, `sub = repo:SeunScape/fineract-target:pull_request` |
| | AWS managed `ReadOnlyAccess`, plus inline `state-access`: read/write on `target/terraform.tfstate` and its `.tflock`, `kms:Decrypt`/`GenerateDataKey` on the key |
| IAM role `gha-apply` | Trust: `aud = sts.amazonaws.com`, `sub = repo:SeunScape/fineract-target:environment:aws-target` |
| | Inline `state-and-key`: target state and lock file, use of the key, `kms:CreateGrant` only for AWS services |
| | Inline `network-and-vpn`: EC2 VPC, subnet, route table, security group, VGW, customer gateway and VPN connection actions, limited to `eu-west-2` |
| | Inline `rds-and-secrets`: RDS instance, subnet group and parameter group actions (`eu-west-2`), RDS service-linked role creation, Secrets Manager secrets in this account and region |

Neither role has `AdministratorAccess`. Neither role can touch `bootstrap/terraform.tfstate`.

## Steps run

From `bootstrap/`:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan          # Plan: 16 to add, 0 to change, 0 to destroy
terraform apply tfplan              # Apply complete! Resources: 16 added
```

Then the state was moved into the bucket it had just created. `backend.tf` was added:

```hcl
terraform {
  backend "s3" {
    bucket       = "fineract-target-tfstate-755431180020"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    kms_key_id   = "alias/fineract-target"
    use_lockfile = true
  }
}
```

```bash
terraform init -migrate-state -force-copy
terraform plan                      # No changes. Your infrastructure matches the configuration.
rm terraform.tfstate terraform.tfstate.backup tfplan
```

No local state file remains. Locking uses S3 native lock files; there is no DynamoDB table.

## Outputs

| Output | Value |
|---|---|
| `state_bucket` | `fineract-target-tfstate-755431180020` |
| `kms_key_arn` | `arn:aws:kms:eu-west-2:755431180020:key/fd0d62d0-3027-4271-a84e-ae6d4a819186` |
| `kms_alias` | `alias/fineract-target` |
| `gha_plan_role_arn` | `arn:aws:iam::755431180020:role/gha-plan` |
| `gha_apply_role_arn` | `arn:aws:iam::755431180020:role/gha-apply` |

None of these are secrets. The role ARNs and region are stored as GitHub repository variables in Step 2.

## Verification

| Check | Command | Expected | Result |
|---|---|---|---|
| Versioning | `aws s3api get-bucket-versioning --bucket fineract-target-tfstate-755431180020` | `Enabled` | |
| Public access | `aws s3api get-public-access-block --bucket fineract-target-tfstate-755431180020` | all four `true` | |
| Key rotation | `aws kms get-key-rotation-status --key-id alias/fineract-target` | `true` | |
| Trust policies | IAM console, both roles | exact repo; `gha-apply` names `aws-target` | |
| No local state | `ls bootstrap/` | no `terraform.tfstate` | Confirmed |

## Changing the bootstrap layer later

Changes here are also manual, by an admin, from a laptop. The pipeline roles can't modify this layer or
read its state. Run `terraform plan` from `bootstrap/` with the admin profile, review it, then apply.
Record each change in `docs/change-log.md`.

## Tearing it down (end of project only)

The state lives in the bucket being destroyed, so destroy in this order:

1. Destroy `envs/target/` through the pipeline first.
2. Remove `backend.tf` and run `terraform init -migrate-state` to bring the state back to local.
3. Empty the bucket, including all object versions (versioning is on).
4. `terraform destroy` from `bootstrap/`. The KMS key enters a 30-day pending-deletion window.
