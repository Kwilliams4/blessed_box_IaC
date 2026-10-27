resource "aws_db_subnet_group" "prod_mysql" {
  name       = "prod-rds"
  subnet_ids = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]

  tags = {
    Name        = "prod-rds"
    Environment = "prod"
  }
}

resource "aws_db_parameter_group" "prod_mysql" {
  name   = "prod-mysql"
  family = "mysql8.0"

  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "long_query_time"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name        = "prod-mysql"
    Environment = "prod"
  }
}

resource "aws_db_instance" "prod_mysql" {
  identifier              = "blessedbox-prod-mysql"
  snapshot_identifier     = "prod-rds"
  allocated_storage       = 50
  max_allocated_storage   = 200
  storage_type            = "gp3"
  storage_encrypted       = true
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  db_name                 = "blessedbox_prod"
  username                = "bb_prod_admin"
  password                = var.db_master_password
  multi_az                = true
  db_subnet_group_name    = aws_db_subnet_group.prod_mysql.name
  parameter_group_name    = aws_db_parameter_group.prod_mysql.name
  vpc_security_group_ids  = [aws_security_group.prod_db.id]
  publicly_accessible     = false
  backup_retention_period = 7
  copy_tags_to_snapshot   = true
  enabled_cloudwatch_logs_exports = [
    "error",
    "slowquery"
  ]
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "blessedbox-prod-final-${data.aws_caller_identity.current.account_id}"
  apply_immediately         = false

  tags = {
    Name        = "blessedbox-prod-mysql"
    Environment = "prod"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "prod_rds_error" {
  name              = "/aws/rds/instance/${aws_db_instance.prod_mysql.identifier}/error"
  retention_in_days = 365

  tags = {
    Environment = "prod"
  }
}

resource "aws_cloudwatch_log_group" "prod_rds_slowquery" {
  name              = "/aws/rds/instance/${aws_db_instance.prod_mysql.identifier}/slowquery"
  retention_in_days = 365

  tags = {
    Environment = "prod"
  }
}
