# modules/compute/aws-eks/main.tf
# EKS Cluster with managed node groups and hardened defaults:
# - Private API endpoint in staging/prod (configurable)
# - Optional KMS secrets encryption
# - Core managed add-ons (coredns, kube-proxy, vpc-cni) + optional EBS CSI + CloudWatch Observability

# ─── Variables ───────────────────────────────────────────────────
variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "node_groups" { type = any }

variable "public_access_cidrs" {
  type    = list(string)
  default = []
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "enable_secrets_encryption" {
  type    = bool
  default = false
}

variable "cluster_log_retention_days" {
  type    = number
  default = 30
}

variable "enable_ebs_csi_addon" {
  type    = bool
  default = true
}

variable "enable_cloudwatch_observability_addon" {
  type    = bool
  default = false
}

variable "enable_cluster_autoscaler" {
  type    = bool
  default = true
}

variable "enable_aws_load_balancer_controller" {
  type    = bool
  default = true
}

# ─── Data Sources ────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

# ─── IAM Role for EKS Control Plane ──────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── CloudWatch Log Group (control plane logs retention) ──────────
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
}

# ─── KMS key for Kubernetes secrets encryption (optional) ─────────
resource "aws_kms_key" "eks" {
  count                   = var.enable_secrets_encryption ? 1 : 0
  description             = "KMS key for EKS secrets encryption (${var.cluster_name})"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSClusterRoleUse"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.cluster.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "eks" {
  count         = var.enable_secrets_encryption ? 1 : 0
  name          = "alias/eks-${var.cluster_name}"
  target_key_id = aws_kms_key.eks[0].key_id
}

# ─── Security Group for cluster API ──────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-cluster-sg" }
}

# ─── EKS Cluster ─────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : []
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  dynamic "encryption_config" {
    for_each = var.enable_secrets_encryption ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.eks[0].arn
      }
      resources = ["secrets"]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster
  ]
}

# ─── OIDC Provider for IRSA ──────────────────────────────────────
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ─── IAM Role for Node Groups ─────────────────────────────────────
resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Needed when enabling EBS CSI addon without a dedicated IRSA role.
resource "aws_iam_role_policy_attachment" "node_ebs_csi" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Needed for CloudWatch Observability addon (agent permissions on nodes).
resource "aws_iam_role_policy_attachment" "node_cloudwatch_agent" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ─── Managed Node Groups ──────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.subnet_ids

  instance_types = lookup(each.value, "instance_types", ["t3.medium"])

  scaling_config {
    min_size     = lookup(each.value, "min_size", 1)
    max_size     = lookup(each.value, "max_size", 3)
    desired_size = lookup(each.value, "desired_size", 1)
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "node-group" = each.key
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_ebs_csi,
    aws_iam_role_policy_attachment.node_cloudwatch_agent,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ─── Managed Add-ons ──────────────────────────────────────────────
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  count                       = var.enable_ebs_csi_addon ? 1 : 0
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count                       = var.enable_cloudwatch_observability_addon ? 1 : 0
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# ─── Outputs ─────────────────────────────────────────────────────
output "cluster_name" { value = aws_eks_cluster.main.name }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_certificate_authority" {
  value     = aws_eks_cluster.main.certificate_authority[0].data
  sensitive = true
}
output "oidc_provider" {
  value = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.cluster.arn }

output "kms_key_arn" {
  value       = try(aws_kms_key.eks[0].arn, null)
  description = "KMS key ARN used for EKS secrets encryption (null if disabled)"
}