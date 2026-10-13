# Change log

| Date | Phase | Change | Reason |
|---|---|---|---|
| 2026-10-12 | 2 | Fineract app server moved from Phase 2 to Phase 3 | Only needed at cutover; avoids EC2 hours and a NAT decision during the build |
| 2026-10-12 | 2 | Two-layer Terraform design adopted: persistent `bootstrap/`, ephemeral `envs/target/` | Hourly-billed resources only run during sessions; destroyed by the pipeline after each |
| 2026-10-13 | 2 | `gha-plan`/`gha-apply` trust policies switched to GitHub's immutable OIDC subject (owner and repo IDs) | Repo issues ID-based subjects; also stops a renamed or re-created repo of the same name from assuming the roles |
