output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.private : k => s.id }
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.main.name
}

output "rds_endpoint" {
  value = try(aws_db_instance.main[0].endpoint, null)
}
