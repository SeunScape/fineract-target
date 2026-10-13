resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "fineract-target"
  }
}

# Strip all rules from the default security group so nothing can use it.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "fineract-target-default-unused"
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = "${var.region}${each.key}"
  map_public_ip_on_launch = false

  tags = {
    Name = "fineract-target-private-${each.key}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "fineract-target-private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_db_subnet_group" "main" {
  name       = "fineract-target"
  subnet_ids = [for s in aws_subnet.private : s.id]

  tags = {
    Name = "fineract-target"
  }
}

# No egress rules: Terraform removes the default allow-all egress on create.
resource "aws_security_group" "rds" {
  name        = "rds"
  description = "PostgreSQL from the bank LAN over the VPN only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_bank_lan" {
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL from bank LAN"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = var.bank_lan_cidr
}
