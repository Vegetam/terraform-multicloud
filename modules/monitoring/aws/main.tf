# modules/monitoring/aws/main.tf
# CloudWatch alarms for EKS and RDS + SNS alert topic

variable "project_name" { type = string }
variable "environment"  { type = string }
variable "eks_cluster"  { type = string }
variable "rds_instance" { type = string }
variable "sns_email"    { type = string }

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── SNS Topic for Alerts ─────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ─── RDS Alarms ──────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization > 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = { DBInstanceIdentifier = var.rds_instance }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120  # 5 GB in bytes
  alarm_description   = "RDS free storage < 5GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { DBInstanceIdentifier = var.rds_instance }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${local.name_prefix}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 150
  alarm_description   = "RDS connections > 150"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { DBInstanceIdentifier = var.rds_instance }
}

# ─── EKS / Node Alarms ───────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "${local.name_prefix}-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EKS node CPU utilization > 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { ClusterName = var.eks_cluster }
}


output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }
