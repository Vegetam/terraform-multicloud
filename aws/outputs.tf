# aws/outputs.tf

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.instance_endpoint
  sensitive   = true
}

output "s3_bucket_arn" {
  description = "App data S3 bucket ARN"
  value       = module.app_storage.bucket_arn
}

output "app_service_account_role_arn" {
  description = "IAM role ARN for the app Kubernetes service account (IRSA)"
  value       = aws_iam_role.app_service_account.arn
}
