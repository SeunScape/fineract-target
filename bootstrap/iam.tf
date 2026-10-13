locals {
  oidc_host = "token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# Trust policies
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${local.github_repo_path}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${local.github_repo_path}:environment:${var.github_environment}"]
    }
  }
}

# ---------------------------------------------------------------------------
# Shared: state bucket and KMS key access for envs/target
# ---------------------------------------------------------------------------

locals {
  target_state_arn = "${aws_s3_bucket.state.arn}/${local.target_state_key}"
  target_lock_arn  = "${local.target_state_arn}.tflock"
}

# ---------------------------------------------------------------------------
# gha-plan
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gha_plan" {
  name                 = "gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "gha_plan" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["target/*"]
    }
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [local.target_state_arn]
  }

  statement {
    sid       = "LockFile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.target_lock_arn]
  }

  statement {
    sid       = "StateKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "gha_plan" {
  name   = "state-access"
  role   = aws_iam_role.gha_plan.id
  policy = data.aws_iam_policy_document.gha_plan.json
}

# ---------------------------------------------------------------------------
# gha-apply: scoped to the services envs/target uses
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gha_apply" {
  name                 = "gha-apply"
  assume_role_policy   = data.aws_iam_policy_document.trust_apply.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gha_apply_state" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["target/*"]
    }
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [local.target_state_arn]
  }

  statement {
    sid       = "LockFile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.target_lock_arn]
  }

  statement {
    sid = "KeyUse"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.main.arn]
  }

  statement {
    sid       = "KeyGrantsForAwsServices"
    actions   = ["kms:CreateGrant"]
    resources = [aws_kms_key.main.arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid       = "KeyLookup"
    actions   = ["kms:ListAliases"]
    resources = ["*"]
  }

  # RDS describes the Secrets Manager default key while creating a managed master password.
  statement {
    sid       = "DescribeSecretsManagerDefaultKey"
    actions   = ["kms:DescribeKey"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${var.region}:${local.account_id}:key/*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = ["alias/aws/secretsmanager"]
    }
  }
}

data "aws_iam_policy_document" "gha_apply_network" {
  statement {
    sid       = "Ec2Read"
    actions   = ["ec2:Describe*", "ec2:GetVpnConnectionDeviceTypes", "ec2:GetVpnTunnelReplacementStatus"]
    resources = ["*"]
  }

  statement {
    sid = "Ec2VpcAndVpn"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateVpnGateway",
      "ec2:DeleteVpnGateway",
      "ec2:AttachVpnGateway",
      "ec2:DetachVpnGateway",
      "ec2:EnableVgwRoutePropagation",
      "ec2:DisableVgwRoutePropagation",
      "ec2:CreateCustomerGateway",
      "ec2:DeleteCustomerGateway",
      "ec2:CreateVpnConnection",
      "ec2:DeleteVpnConnection",
      "ec2:ModifyVpnConnection",
      "ec2:ModifyVpnConnectionOptions",
      "ec2:ModifyVpnTunnelOptions",
      "ec2:CreateVpnConnectionRoute",
      "ec2:DeleteVpnConnectionRoute",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

data "aws_iam_policy_document" "gha_apply_data" {
  statement {
    sid = "Rds"
    actions = [
      "rds:Describe*",
      "rds:ListTagsForResource",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "rds:CreateDBInstance",
      "rds:ModifyDBInstance",
      "rds:DeleteDBInstance",
      "rds:RebootDBInstance",
      "rds:DeleteDBInstanceAutomatedBackup",
      "rds:CreateDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:CreateDBParameterGroup",
      "rds:ModifyDBParameterGroup",
      "rds:ResetDBParameterGroup",
      "rds:DeleteDBParameterGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "RdsServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/aws-service-role/rds.amazonaws.com/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["rds.amazonaws.com"]
    }
  }

  statement {
    sid = "SecretsManager"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:RotateSecret",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${local.account_id}:secret:*"]
  }
}

resource "aws_iam_role_policy" "gha_apply_state" {
  name   = "state-and-key"
  role   = aws_iam_role.gha_apply.id
  policy = data.aws_iam_policy_document.gha_apply_state.json
}

resource "aws_iam_role_policy" "gha_apply_network" {
  name   = "network-and-vpn"
  role   = aws_iam_role.gha_apply.id
  policy = data.aws_iam_policy_document.gha_apply_network.json
}

resource "aws_iam_role_policy" "gha_apply_data" {
  name   = "rds-and-secrets"
  role   = aws_iam_role.gha_apply.id
  policy = data.aws_iam_policy_document.gha_apply_data.json
}
