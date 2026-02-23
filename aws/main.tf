# ============================================================
# AWS Infrastructure — Enterprise-Ready Baseline
# Provisions: VPC, EKS, RDS, S3, IAM roles (IRSA)
#
# Authentication: Use AWS_PROFILE locally or OIDC in CI/CD.
# No static credentials are committed.
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Used by the EKS module for OIDC thumbprint discovery.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend config is provided via -backend-config=<file>
  # Example: terraform init -backend-config=../environments/dev/backend-aws.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "github.com/yourname/3-terraform-multicloud"
    }
  }
}

locals {
  # Production posture: private API endpoint by default in staging/prod.
  eks_endpoint_public_access  = var.environment == "dev"
  eks_endpoint_private_access = true

  # NOTE: in dev, restrict access to your corporate/VPN CIDR via var.eks_public_access_cidrs.
  # Do not use 0.0.0.0/0 in real environments — not even in dev.
  eks_public_access_cidrs = local.eks_endpoint_public_access ? var.eks_public_access_cidrs : []

  # Enable secrets encryption for non-dev environments.
  eks_enable_secrets_encryption = var.environment != "dev"

  # Keep control plane logs longer in production.
  eks_cluster_log_retention_days = var.environment == "prod" ? 90 : 30

  # Observability addon is typically enabled in staging/prod.
  eks_enable_cloudwatch_observability = var.environment != "dev"
}

# ─── Networking ───────────────────────────────────────────────────
module "vpc" {
  source = "../modules/networking/aws"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnet_cidrs
  private_subnets    = var.private_subnet_cidrs
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod" # Cost optimization for non-prod
}

# ─── EKS Cluster ─────────────────────────────────────────────────
module "eks" {
  source = "../modules/compute/aws-eks"

  cluster_name = "${var.project_name}-${var.environment}"
  # FIX: aggiornato da 1.28 (EOL su EKS) a 1.30
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  endpoint_public_access  = local.eks_endpoint_public_access
  endpoint_private_access = local.eks_endpoint_private_access
  public_access_cidrs     = local.eks_public_access_cidrs

  enable_secrets_encryption             = local.eks_enable_secrets_encryption
  cluster_log_retention_days            = local.eks_cluster_log_retention_days
  enable_ebs_csi_addon                  = true
  enable_cloudwatch_observability_addon = local.eks_enable_cloudwatch_observability

  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = var.environment == "prod" ? 3 : 1
      max_size       = var.environment == "prod" ? 10 : 3
      desired_size   = var.environment == "prod" ? 3 : 1
    }
  }

  enable_cluster_autoscaler           = true
  enable_aws_load_balancer_controller = true
}

# ─── RDS PostgreSQL ──────────────────────────────────────────────
module "rds" {
  source = "../modules/storage/aws-rds"

  identifier            = "${var.project_name}-${var.environment}"
  engine                = "postgres"
  engine_version        = "15.4"
  instance_class        = var.environment == "prod" ? "db.r6g.large" : "db.t3.micro"
  allocated_storage     = var.environment == "prod" ? 100 : 20
  max_allocated_storage = var.environment == "prod" ? 500 : 50

  db_name  = var.db_name
  username = var.db_username

  # Password sourced from AWS Secrets Manager — NOT stored in tfvars.
  manage_master_user_password = true

  vpc_security_group_ids = [module.vpc.database_security_group_id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name

  backup_retention_period = var.environment == "prod" ? 30 : 7
  deletion_protection     = var.environment == "prod"
  skip_final_snapshot     = var.environment != "prod"
  multi_az                = var.environment == "prod"
  storage_encrypted       = true
}

# ─── S3 Buckets ──────────────────────────────────────────────────
module "app_storage" {
  source = "../modules/storage/aws-s3"

  bucket_name = "${var.project_name}-${var.environment}-app-data"
  environment = var.environment

  versioning_enabled     = true
  server_side_encryption = "AES256"
  block_public_access    = true

  lifecycle_rules = [
    {
      id     = "transition-to-ia"
      status = "Enabled"
      transition = {
        days          = 30
        storage_class = "STANDARD_IA"
      }
    }
  ]
}

# ─── IAM — EKS Service Account Roles (IRSA) ──────────────────────
resource "aws_iam_role" "app_service_account" {
  name = "${var.project_name}-${var.environment}-app-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:app:app-service-account"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_s3_access" {
  name = "s3-access"
  role = aws_iam_role.app_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.app_storage.bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = module.app_storage.bucket_arn
      }
    ]
  })
}

# ─── CloudWatch Monitoring ────────────────────────────────────────
module "monitoring" {
  source = "../modules/monitoring/aws"

  project_name = var.project_name
  environment  = var.environment
  eks_cluster  = module.eks.cluster_name
  rds_instance = module.rds.instance_id
  sns_email    = var.alert_email
}
