# Phase 2 Walkthrough: AWS Target Environment and VPN (cost-optimised)

**Goal of the phase:** an empty, secured AWS home for the bank (RDS for PostgreSQL in private subnets), deployed only through an approved pipeline and reachable from the Droplet over a Site-to-Site VPN. Phase 3 migrates data into it.

**How to use this:** same as Phase 1. One step at a time, paste the **Prompt for Claude Code**, read every diff, run **You verify** yourself, and move on only when **Done when** is true. Bring "why" questions to your mentor.

---

## The cost design (read this first)

| Decision | Saves | Trade-off you record in an ADR |
|---|---|---|
| **Two layers.** `bootstrap/` holds the near-free resources (state bucket, KMS key, OIDC, IAM roles) and is persistent. `envs/target/` holds everything billed hourly and is destroyed after every session. | Hourly items only run when you're working | Two state files to manage |
| **No NAT gateway, no internet gateway.** RDS doesn't need internet access. | A NAT gateway billing about $0.05/hr plus data, around $35+/month if forgotten | Nothing in the VPC can reach the internet. That's fine for Phase 2; Phase 3 decides how the Fineract app server gets its images. |
| **Fineract app server moved to Phase 3.** It's only needed at cutover. | Hours of EC2 and the NAT decision | Change-log entry (plan said Phase 2) |
| **RDS `db.t4g.micro`, single-AZ by default.** Multi-AZ is a variable, switched on only for the Phase 3 cutover session. | Halves RDS cost during build | Single-AZ isn't production-grade; documented as a lab setting |
| **No test EC2 instance.** Connectivity is tested *from the Droplet* to RDS. | An instance plus SSM endpoints | The AWS → Droplet direction is proven in Phase 3 by the DMS connection test |
| **GitHub Actions on a public repo.** | CodePipeline/CodeBuild charges | Deployment orchestration sits with a third party; mitigated by OIDC (no stored AWS keys) |
| **RDS-managed master password** in Secrets Manager, encrypted with your KMS key | One less secret to manage | None |
| **Daily cost guard.** A scheduled read-only workflow fails, and GitHub emails you, if billable resources are still running at night | Catches the forgotten session | None |

**Approximate running costs (eu-west-2, on-demand; confirm in the AWS Pricing Calculator, which feeds your business case):**

| Item | Cost | When it bills |
|---|---|---|
| Site-to-Site VPN connection | about $0.05/hr | Only during sessions |
| RDS db.t4g.micro single-AZ | about $13/month on-demand, roughly $0.018/hr | Only during sessions |
| RDS gp3 storage, 20 GB | cents per session | Only during sessions |
| Secrets Manager (DB password, VPN keys) | $0.40 per secret per month, prorated | Only during sessions |
| KMS customer-managed key | about $1/month | Always (bootstrap layer) |
| S3 state bucket | effectively $0 | Always |

A 4-hour session costs roughly **$0.30–0.40**. Phase 2 in total should land **under $5**, plus a dollar or two for the KMS key. The danger isn't the hourly rate; it's forgetting to destroy. A VPN plus RDS left running for a month costs around $50.

**Also check:** Billing console → Credits and Free Tier. Newer AWS accounts receive sign-up credits that may cover all of this. Record real costs in `docs/cost-record.md` anyway.

---

## Step 0: Decisions and housekeeping (no AWS spend)

1. **Region ADR** (`docs/adr/0002-aws-region.md`, you write it): eu-west-2 London vs af-south-1 Cape Town vs the Lagos Local Zone. Choose London for V1; state that a real Nigerian bank must resolve data residency with compliance.
2. **CI/CD tool ADR** (you write it): GitHub Actions vs CodePipeline. Choose GitHub Actions on cost and portfolio visibility; note the third-party trust trade-off and OIDC as the mitigation.
3. **Change log entries:** Fineract app server moved to Phase 3; two-layer design adopted.
4. **Daily budget:** in AWS Budgets, add a *daily* cost budget of $2 with an email alert at 100%. Your monthly budget catches trends; the daily one catches a forgotten session within a day.
5. **Admin access for bootstrap:** use your IAM Identity Center (or admin IAM user) profile via `aws configure sso` or `aws configure`. This is the one time a human applies Terraform to AWS.
6. **Create the repo** `fineract-target` on GitHub as **public**, with `.gitignore` (same as the source repo), and put `CLAUDE.md` and `.claude/settings.json` from your mentor in it.

**Done when:** both ADRs are drafted, the daily budget exists, `aws sts get-caller-identity` works with your admin profile, and the repo exists with its Claude Code files committed.

---

## Step 1: Bootstrap layer (persistent, near-free)

**Goal:** the things the pipeline needs before it can exist. This solves the chicken-and-egg problem: a pipeline can't create the bucket that stores its own state, or the role it logs in with.

**Prompt for Claude Code:**
> Create `bootstrap/` per CLAUDE.md. Resources: (1) S3 state bucket with a globally unique name, versioning on, SSE-KMS using (2), all public access blocked, bucket policy denying non-TLS requests; (2) a KMS customer-managed key with rotation enabled and an alias `alias/fineract-target`; (3) the GitHub Actions OIDC provider; (4) IAM role `gha-plan` trusted only for `repo:<OWNER>/fineract-target:pull_request`, with ReadOnlyAccess plus read/write on the state bucket objects and lock files and kms:Decrypt/GenerateDataKey on the key; (5) IAM role `gha-apply` trusted only for `repo:<OWNER>/fineract-target:environment:aws-target`, with a policy scoped to the services in this repo (EC2 VPC/VPN APIs, RDS, Secrets Manager, KMS use of this key, state bucket), not AdministratorAccess. Both trust policies must check `aud = sts.amazonaws.com`. Local state for now. Run init, fmt, validate and plan, then stop.

**Then (you approve):** `terraform apply` in `bootstrap/`. After that, add an S3 backend block pointing at the new bucket with key `bootstrap/terraform.tfstate` and `use_lockfile = true`, and run `terraform init -migrate-state`. The bootstrap state now lives in the bucket it created.

**You verify:**
- `aws s3api get-bucket-versioning --bucket <name>` → `Enabled`
- `aws s3api get-public-access-block --bucket <name>` → all four `true`
- `aws kms get-key-rotation-status --key-id alias/fineract-target` → `true`
- IAM console: both roles' trust policies name your exact repo, and `gha-apply` names the `aws-target` environment
- No local `terraform.tfstate` left in `bootstrap/` after migration

**Done when:** bootstrap state is in S3, both roles exist, and `docs/bootstrap.md` records exactly how you did it (the one manual apply).

---

## Step 2: The pipeline (GitHub Actions)

**Goal:** every change to `envs/target/` is planned, reviewed, approved, then applied by the pipeline, leaving an audit trail.

**First, in GitHub (you do this):** Settings → Environments → create `aws-target` with yourself as **required reviewer**. Store the two role ARNs and the region as repository **variables** (not secrets; they aren't sensitive).

**Prompt for Claude Code:**
> Create three workflows in `.github/workflows/`, with all actions pinned by full commit SHA, Terraform version pinned, and `permissions: id-token: write, contents: read` (plus `pull-requests: write` for plan). (1) `plan.yml`: on pull_request touching `envs/target/**`, assume `gha-plan`, run fmt check, validate and plan with `-var enable_vpn=true -var enable_rds=true` and a dummy `source_public_ip`, and post the plan summary as a PR comment. (2) `deploy.yml`: workflow_dispatch with inputs `enable_rds`, `enable_vpn`, `multi_az` (default false) and `source_public_ip`; job uses environment `aws-target`, assumes `gha-apply`, runs plan then apply of that saved plan. (3) `destroy.yml`: workflow_dispatch, environment `aws-target`, assumes `gha-apply`, runs plan -destroy then applies it. Never print sensitive values. Create a minimal `envs/target/` with only the backend (key `target/terraform.tfstate`, `use_lockfile = true`), provider with `default_tags`, and variables, so the workflows can run. Open a PR.

**You verify:**
- The PR shows a plan comment with **0 to add** (nothing defined yet).
- Run `deploy.yml` from the Actions tab: it **pauses for your approval** before applying.
- CloudTrail event history shows `AssumeRoleWithWebIdentity` for `gha-plan` and `gha-apply`. That's your audit evidence.

**Done when:** a no-op change has gone PR → plan → merge → deploy with approval, and screenshots of the approval gate and the CloudTrail entries are saved in `docs/evidence/phase-2-pipeline.md`.

---

## Step 3: Network (VPC, private subnets only)

**Goal:** the bank's private network in AWS. VPCs, subnets and route tables cost nothing.

**Prompt for Claude Code:**
> In `envs/target/`, add the VPC and two private subnets per the network plan in CLAUDE.md, one route table associated with both, and a DB subnet group. No IGW, no NAT. Add a security group `rds` allowing TCP 5432 only from `172.20.0.0/24`, with no egress rules beyond what RDS needs. Open a PR.

**You verify:** in the PR plan, confirm there's no `aws_internet_gateway`, no `aws_nat_gateway`, and no `0.0.0.0/0` anywhere. Merge, then run `deploy.yml` (enable flags false) and approve.

**Done when:** the VPC exists, deployed by the pipeline, and the plan evidence shows no internet path.

---

## Step 4: RDS for PostgreSQL

**Goal:** the empty target database.

**Before prompting:** check `docs/fineract-notes.md` in the source repo for the source PostgreSQL major version. The target uses the **same major version** (like-for-like migration).

**Prompt for Claude Code:**
> Add RDS PostgreSQL to `envs/target/`, created only when `enable_rds = true`. Engine major version `<N>` (pin the minor), settings exactly as in CLAUDE.md cost rules, `multi_az = var.multi_az`, storage encrypted with the bootstrap KMS key, `manage_master_user_password = true` with that KMS key, `publicly_accessible = false`, security group `rds`, custom parameter group with `rds.force_ssl = 1`, `backup_retention_period = 1`, auto minor version upgrade off. Output the endpoint only. Open a PR.

**Then:** merge, run `deploy.yml` with `enable_rds = true`, approve. RDS takes about 5–10 minutes to create.

**You verify:**
- `aws rds describe-db-instances` → `PubliclyAccessible: false`, `StorageEncrypted: true`, `MultiAZ: false`, the KMS key ARN is yours
- The master secret is in Secrets Manager and is encrypted with your key
- Then **run `destroy.yml`** unless you're going straight into Step 5

**Done when:** RDS deploys and destroys cleanly through the pipeline.

---

## Step 5: Site-to-Site VPN

**Goal:** an encrypted tunnel between the Droplet ("the bank's data centre") and the AWS VPC, standing in for Direct Connect.

**Two things that trip people up, already designed around:**
- **The Droplet's IP changes on every rebuild,** so the customer gateway is recreated each session. That's fine, because the VPN lives in the ephemeral layer anyway. You pass the current IP as the `source_public_ip` input to `deploy.yml`.
- **DigitalOcean's cloud firewall only filters TCP, UDP and ICMP; it can't allow ESP.** So strongSwan must force UDP encapsulation (NAT-T on UDP 4500), and the firewall opens UDP 500 and 4500 only to AWS's two tunnel IPs.

**5a. AWS side. Prompt for Claude Code:**
> Add a VPN to `envs/target/`, created only when `enable_vpn = true`: a virtual private gateway attached to the VPC, route propagation on the private route table, a customer gateway using `var.source_public_ip`, and a VPN connection with static routing and a static route to `172.20.0.0/24`. Both tunnels: IKEv2 only, AES-256, SHA2-256, DH group 14 or higher. Generate both pre-shared keys with random_password (8–64 characters, letters, digits, `.` and `_` only, not starting with 0) and store them in one Secrets Manager secret encrypted with the bootstrap key, `recovery_window_in_days = 0`. Output only the two tunnel outside IPs. Open a PR.

**5b. Droplet side, in the `fineract-source` repo. Prompt for Claude Code there:**
> Add a `aws_tunnel_ips` list variable (default empty) to the firewall: when set, allow inbound UDP 500 and 4500 from those IPs only. This must not replace the Droplet. Then create `scripts/configure-vpn.sh` (not cloud-init, so the Droplet isn't replaced) that installs strongSwan, creates a dummy interface with `172.20.0.10/24`, and writes a swanctl config for both tunnels: IKEv2, the same algorithms as the AWS side, `encap = yes`, local_ts `172.20.0.0/24`, remote_ts `10.20.0.0/16`, DPD and start_action start. The script reads the tunnel IPs as arguments and the PSKs from stdin, and never writes PSKs to the repo or shell history.

**Session flow (you run it):** `terraform apply` the source repo (Droplet up) → run `deploy.yml` with `enable_rds`, `enable_vpn` and the Droplet IP → note the two tunnel IPs from the workflow output → apply the source firewall with `aws_tunnel_ips` → fetch the PSKs with `aws secretsmanager get-secret-value` and pipe them into `configure-vpn.sh` over SSH.

**You verify:**
- On the Droplet: `sudo swanctl --list-sas` shows established SAs
- `aws ec2 describe-vpn-connections` → tunnel status `UP` (at least one; both is better)
- `nmap -Pn <droplet-ip>` from your laptop still shows only port 22 (the UDP ports are open only to AWS)

**Done when:** at least one tunnel is UP and the Droplet still exposes nothing new to the internet.

---

## Step 6: Connectivity test

**Goal:** prove traffic flows from the bank's network to RDS through the tunnel.

On the Droplet (Ubuntu 24.04 ships `postgresql-client`):
```bash
pg_isready -h <rds-endpoint> -p 5432
psql "host=<rds-endpoint> dbname=postgres user=<master-user> sslmode=require" -c "select version();"
```
Retrieve the password from Secrets Manager on your laptop and type it at the prompt. Never put it in a command or file. Run tests from the host, or a container with `--network host`. Normal Docker networking won't route through the tunnel.

**You verify:** both commands succeed. Then test the negative: the same `psql` from your laptop must fail, because RDS isn't reachable from the internet.

**Known limit (state it in the evidence):** this proves the Droplet → AWS direction. DMS connects AWS → Droplet, which Phase 3 proves with the DMS endpoint connection test. Note now for Phase 3: the source PostgreSQL container is bound to `127.0.0.1`, so DMS won't reach it until Phase 3 rebinds it to `172.20.0.10`.

**Done when:** `docs/evidence/phase-2-connectivity.md` holds the SA list, the tunnel status, the successful `psql` output, and the failed laptop attempt.

---

## Step 7: Close the session and the phase

1. Run `destroy.yml` and approve. Then `terraform destroy` the Droplet (source repo).
2. **Check for leftovers:** RDS console (instances and *snapshots*), VPC → VPN connections, Secrets Manager (no fineract secrets left), Elastic IPs (none should exist). Bootstrap resources should remain.
3. Add each session to `docs/cost-record.md`, then compare against Cost Explorer a day later (AWS billing data lags).
4. **Cost guard. Prompt for Claude Code:**
   > Add `.github/workflows/cost-guard.yml`: scheduled daily at 22:00 UTC, assumes `gha-plan` (read-only), and fails if any RDS instance, VPN connection or NAT gateway tagged `project=fineract-migration` exists in eu-west-2. The failure triggers GitHub's email notification.
5. **Phase 2 deliverables:** architecture diagram (VPC, subnets, RDS, VGW, tunnel, Droplet), ADRs (region, CI/CD tool, network design, VPN as a Direct Connect stand-in, two-layer cost design), evidence files, and the Phase 2 blog post. The cost design table above is strong blog material.

**Phase 2 is done when:** the whole target environment can be brought up and torn down through the pipeline with approvals, the tunnel test passes, and every artefact above is committed.
