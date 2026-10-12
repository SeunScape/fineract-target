# Change log

| Date | Phase | Change | Reason |
|---|---|---|---|
| 2026-10-12 | 2 | Fineract app server moved from Phase 2 to Phase 3 | Only needed at cutover; avoids EC2 hours and a NAT decision during the build |
| 2026-10-12 | 2 | Two-layer Terraform design adopted: persistent `bootstrap/`, ephemeral `envs/target/` | Hourly-billed resources only run during sessions; destroyed by the pipeline after each |
