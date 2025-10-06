# RDS Module - Managed PostgreSQL Database

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  family = "postgres16"
  name   = "${var.project_name}-${var.environment}-db-params"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log statements taking more than 1 second
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-params"
  })
}

# Random password for database
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine configuration
  engine                = "postgres"
  engine_version        = "16"
  instance_class        = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password != "" ? var.db_password : random_password.db_password.result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.database_security_group_id]
  port                   = 5432

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup and maintenance
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Deletion protection and snapshots
  deletion_protection       = false # Set to true in production
  delete_automated_backups  = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  skip_final_snapshot       = false

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  # Multi-AZ for high availability (disable for cost savings in dev)
  multi_az = var.environment == "prod" ? true : false

  # Publicly accessible (should be false for security)
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-postgres"
    Type = "Database"
  })

  depends_on = [aws_db_subnet_group.main]
}

# IAM role for RDS monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  })
}

# Attach the AWS managed policy for RDS monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Log Group for RDS logs
resource "aws_cloudwatch_log_group" "rds_logs" {
  name              = "/aws/rds/instance/${aws_db_instance.main.id}/postgresql"
  retention_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-rds-logs"
  })
}

# Secrets Manager secret for database credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-${var.environment}-db-credentials"
  description = "Database credentials for ${var.project_name} ${var.environment}"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password != "" ? var.db_password : random_password.db_password.result
    endpoint = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    dbname   = var.db_name
  })
}
