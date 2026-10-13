# Phase 2 evidence: pipeline

Shows that a change to `envs/target/` goes PR → plan → merge → approved deploy, and that each step
authenticates to AWS through GitHub OIDC with a short-lived role session (no stored keys).

Account `755431180020`, region `eu-west-2`. Date 2026-10-13.

## Path of the no-op change

| Step | Record | Result |
|---|---|---|
| PR opened | [PR #1](https://github.com/SeunScape/fineract-target/pull/1) | `plan.yml` ran as `gha-plan` |
| Plan | [run 38414321048](https://github.com/SeunScape/fineract-target/actions/runs/38414321048) | `No changes. Your infrastructure matches the configuration.` posted to the PR |
| Merge | `0445524` on `main` | Squash merge of PR #1 |
| Deploy requested | [run 38416176792](https://github.com/SeunScape/fineract-target/actions/runs/38416176792), created 14:45:55Z | `enable_vpn=false`, `enable_rds=false`, `multi_az=false` |
| Approval gate | Environment `aws-target`, required reviewer | Approved by `SeunScape` |
| Apply | Same run, finished 14:48:58Z | `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` |

## Approval gate

<!-- Screenshot: the deploy run paused at "Waiting for review" on aws-target -->
![Approval gate](img/phase-2-approval-gate.png)

## CloudTrail: role assumptions

`AssumeRoleWithWebIdentity`, eu-west-2. The web identity is GitHub's immutable OIDC subject
(owner and repo IDs), which the trust policy of each role matches exactly.

| Time (UTC) | Role | Session name | Web identity (`sub`) | Result | Event ID |
|---|---|---|---|---|---|
| 14:42:14 | `gha-plan` | `gha-plan-38414321048` | `repo:SeunScape@69199129/fineract-target@1417222926:pull_request` | Success | `df7be88d-a4a8-4110-8c16-888525fea37e` |
| 14:48:37 | `gha-apply` | `gha-apply-38416176792` | `repo:SeunScape@69199129/fineract-target@1417222926:environment:aws-target` | Success | `cf05f436-befb-4685-aa94-136e3ffdfd46` |

The session name carries the GitHub run ID, so each AWS session traces back to one workflow run.

<!-- Screenshot: CloudTrail event history filtered on AssumeRoleWithWebIdentity -->
![CloudTrail event history](img/phase-2-cloudtrail.png)

## Refused assumption (trust policy working)

The first plan run (14:33:13–14:34:02Z) was refused 12 times with `AccessDenied`. The repo issues the
immutable subject `repo:SeunScape@69199129/fineract-target@1417222926:pull_request`; the trust policy
at that time named `repo:SeunScape/fineract-target:pull_request`. The trust policies were updated in
PR #2 (see `docs/bootstrap.md`), after which the same workflow authenticated.
