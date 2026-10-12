# CLAUDE.md — fineract-target

## Project context
This repo builds the **AWS target environment** for a portfolio migration project. A fictional Nigerian
microfinance bank's Apache Fineract system (PostgreSQL, Mifos web UI) currently runs on a DigitalOcean
Droplet (separate repo: `fineract-source`). This repo builds where it migrates to: RDS for PostgreSQL,
reached from the Droplet over an AWS Site-to-Site VPN. Phase 3 adds AWS DMS.

## Stack
- AWS region: eu-west-2 (London). See `docs/adr/`.
- Terraform >= 1.11, AWS provider pinned in `versions.tf`
- Two layers:
  - `bootstrap/`: persistent, applied by hand once. State bucket, KMS key, GitHub OIDC provider, IAM roles.
  - `envs/target/`: ephemeral, deployed only by the GitHub Actions pipeline. VPC, RDS, VPN.
- Remote state: S3 with native locking (`use_lockfile = true`). No DynamoDB table.
- CI/CD: GitHub Actions with OIDC. Plan on pull request; apply and destroy behind the `aws-target` environment approval.

## Network plan (fixed)
- AWS VPC: `10.20.0.0/16`. Private subnets only: `10.20.1.0/24` (AZ a), `10.20.2.0/24` (AZ b).
- No internet gateway, no NAT gateway, no public subnets.
- "Bank LAN" on the Droplet: `172.20.0.0/24`; the Droplet holds `172.20.0.10` on a dummy interface.
- VPN: one Site-to-Site VPN connection to a virtual private gateway, static routing, route to `172.20.0.0/24`.

## Hard rules
1. **Never** run `terraform apply`, `terraform destroy`, or any command that creates, changes or deletes
   real infrastructure without explicit approval in the current message. Show the plan summary first.
2. `envs/target/` is applied **only through the pipeline**, never from a laptop.
3. **No long-lived AWS access keys** anywhere. Pipeline auth is OIDC only.
4. **Never** write secrets into files, workflow logs or Terraform outputs. VPN pre-shared keys and DB
   passwords must never be output or printed. Mark sensitive outputs `sensitive = true`.
5. **Never** commit `*.tfstate`, `*.tfvars`, `.terraform/`, `.env`.
6. RDS is never publicly accessible. Its security group allows 5432 only from `172.20.0.0/24`.
7. Pin versions: Terraform, providers, and GitHub Actions **by full commit SHA**.

## Cost rules (this project is cost-optimised; do not add these without asking)
- No NAT gateway, Transit Gateway, interface VPC endpoints, load balancers, or test EC2 instances.
- RDS: `db.t4g.micro`, single-AZ by default (`multi_az` is a variable, default false), gp3 20 GB,
  no storage autoscaling, Performance Insights off, Enhanced Monitoring off,
  `skip_final_snapshot = true`, `delete_automated_backups = true`, `deletion_protection = false` (lab only).
- Anything billed hourly lives in `envs/target/` so the destroy workflow removes it.
- Tag everything: `project=fineract-migration`, `env=target`, `phase=<n>`, `managed-by=terraform`
  (use provider `default_tags`).

## Wording rule
Describe the design as "using controls expected of CBN-regulated institutions". Never write "CBN compliant".

## How to work with me
- Implementation only. Do not explain concepts, choices or commands; explanations happen elsewhere.
- Keep replies terse: files changed, commands run, result. No code summaries.
- If a step is ambiguous or conflicts with these rules, ask one short question instead of guessing.
- Small, reviewable changes. One concern per change.
- On failure: show the actual error and a one-line diagnosis before changing code.
