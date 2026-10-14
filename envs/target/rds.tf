data "aws_kms_key" "main" {
  key_id = "alias/fineract-target"
}

resource "aws_db_parameter_group" "main" {
  count = var.enable_rds ? 1 : 0

  name   = "fineract-target-pg16"
  family = "postgres16"

  # RDS reports this parameter as pending-reboot; matching it avoids a perpetual diff.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "main" {
  count = var.enable_rds ? 1 : 0

  identifier     = "fineract-target"
  engine         = "postgres"
  engine_version = "16.15"
  instance_class = "db.t4g.micro"
  port           = 5432

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = data.aws_kms_key.main.arn

  username                      = "fineract_admin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = data.aws_kms_key.main.arn

  multi_az               = var.multi_az
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main[0].name

  backup_retention_period    = 1
  auto_minor_version_upgrade = false
  apply_immediately          = true

  performance_insights_enabled = false
  monitoring_interval          = 0

  skip_final_snapshot      = true
  delete_automated_backups = true
  deletion_protection      = false
  copy_tags_to_snapshot    = true

  tags = {
    Name = "fineract-target"
  }
}
