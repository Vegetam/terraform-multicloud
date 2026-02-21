# modules/storage/aws-rds/main.tf
# RDS PostgreSQL with encryption, automated backups, and optional Multi-AZ

variable "identifier"                  { type = string }
variable "engine"                      { type = string; default = "postgres" }
variable "engine_version"              { type = string }
variable "instance_class"              { type = string }
variable "allocated_storage"           { type = number }
variable "max_allocated_storage"       { type = number }
variable "db_name"                     { type = string }
variable "username"                    { type = string }
variable "manage_master_user_password" { type = bool; default = true }
variable "storage_encrypted"           { type = bool; default = true }
variable "multi_az"                    { type = bool; default = false }
variable "backup_retention_period"     { type = number; default = 7 }
variable "deletion_protection"         { type = bool; default = false }
variable "skip_final_snapshot"         { type = bool; default = true }
variable "vpc_security_group_ids"      { type = list(string) }
variable "db_subnet_group_name"        { type = string }

resource "aws_db_instance" "main" {
  identifier        = var.identifier
  engine            = var.engine
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage

  # Auto-scaling storage
  max_allocated_storage = var.max_allocated_storage

  db_name  = var.db_name
  username = var.username

  # Password managed by AWS Secrets Manager
  manage_master_user_password = var.manage_master_user_password

  vpc_security_group_ids = var.vpc_security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name

  # HA & reliability
  multi_az                    = var.multi_az
  backup_retention_period     = var.backup_retention_period
  backup_window               = "03:00-04:00"
  maintenance_window          = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade  = true

  # Security
  storage_encrypted     = var.storage_encrypted
  deletion_protection   = var.deletion_protection
  skip_final_snapshot   = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"

  # Performance Insights (free tier available)
  performance_insights_enabled = true

  tags = { Name = var.identifier }
}

output "instance_id"       { value = aws_db_instance.main.id }
output "instance_endpoint" { value = aws_db_instance.main.endpoint }
output "instance_arn"      { value = aws_db_instance.main.arn }
