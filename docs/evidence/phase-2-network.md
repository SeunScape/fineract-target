# Phase 2 evidence: network

Shows the target VPC was deployed by the pipeline and has no path to or from the internet.

Account `755431180020`, region `eu-west-2`. Date 2026-10-13.

## Change path

| Step | Record | Result |
|---|---|---|
| PR | [PR #4](https://github.com/SeunScape/fineract-target/pull/4) | Plan posted: 10 to add, 0 to change, 0 to destroy |
| Plan | [run 38430071162](https://github.com/SeunScape/fineract-target/actions/runs/38430071162) | Full plan log searched for `0.0.0.0/0`, `internet_gateway`, `nat_gateway`: 0 matches |
| Merge | `d52bbfd` on `main` | |
| Deploy | [run 38431674805](https://github.com/SeunScape/fineract-target/actions/runs/38431674805), 16:34:54Z–16:37:45Z | Approved by `SeunScape` at `aws-target`; `Apply complete! Resources: 10 added, 0 changed, 0 destroyed.` |

## Planned resources

```
create  aws_db_subnet_group.main
create  aws_default_security_group.default
create  aws_route_table.private
create  aws_route_table_association.private["a"]
create  aws_route_table_association.private["b"]
create  aws_security_group.rds
create  aws_subnet.private["a"]
create  aws_subnet.private["b"]
create  aws_vpc.main
create  aws_vpc_security_group_ingress_rule.rds_from_bank_lan
```

## Deployed state (AWS CLI, after apply)

| Check | Result |
|---|---|
| VPC | `vpc-0d34648fdea3a4090`, `10.20.0.0/16` |
| Internet gateways attached | 0 |
| NAT gateways | 0 |
| Route table `fineract-target-private` | `10.20.0.0/16` (local) only |
| Main route table | `10.20.0.0/16` (local) only |
| Security group `rds` (`sg-0ba63a5b28d83f4c5`) | 1 ingress rule: TCP 5432 from `172.20.0.0/24`; 0 egress rules |
| Default security group (`sg-085af56cd9cc7d395`) | 0 ingress, 0 egress rules |

No route leaves the VPC. The bank LAN route (`172.20.0.0/24`) arrives in Step 5 with the VPN.
