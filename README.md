# ☁️ Terraform Multi-Cloud Infrastructure — AWS · Azure · GCP

> Infrastructure as Code demonstrating multi-cloud provisioning across AWS, Azure, and GCP with Terraform — reusable modules, remote state, environment isolation, and keyless CI/CD authentication.

> ⚠️ **PoC / Reference implementation.** No secrets are committed to this repository. All credentials use environment variables or cloud-native secret managers.

---

## 🌐 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     MULTI-CLOUD INFRASTRUCTURE                          │
│                                                                         │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │      AWS        │  │     AZURE        │  │        GCP           │   │
│  │                 │  │                  │  │                      │   │
│  │  VPC            │  │  VNet            │  │  VPC                 │   │
│  │  └─ EKS         │  │  └─ AKS          │  │  └─ GKE              │   │
│  │  └─ RDS PG      │  │  └─ Azure DB PG  │  │  └─ Cloud SQL PG     │   │
│  │  └─ S3          │  │  └─ Blob Storage │  │  └─ Cloud Storage    │   │
│  │  └─ CloudWatch  │  │  └─ Key Vault    │  │  └─ Secret Manager   │   │
│  │  └─ IAM/IRSA    │  │  └─ Monitor+LAW  │  │  └─ Workload ID      │   │
│  └─────────────────┘  └──────────────────┘  └──────────────────────┘   │
│                                                                         │
│  ─────────────────────── Shared Modules ──────────────────────────────  │
│  networking · compute · storage · monitoring                            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
.
├── aws/
│   ├── main.tf          # AWS provider + all module calls
│   ├── variables.tf
│   └── outputs.tf
│
├── azure/
│   ├── main.tf          # Azure provider + all module calls
│   ├── variables.tf
│   └── outputs.tf
│
├── gcp/
│   ├── main.tf          # GCP provider + all module calls
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/
│   ├── networking/
│   │   ├── aws/         # VPC, subnets, NAT, IGW, route tables, SGs ✅
│   │   ├── azure/       # VNet, subnets, NSGs, delegations           ✅
│   │   └── gcp/         # VPC, subnets, Cloud Router, Cloud NAT      ✅
│   ├── compute/
│   │   ├── aws-eks/     # EKS cluster, node groups, IRSA/OIDC        ✅
│   │   └── azure-aks/   # AKS cluster, SystemAssigned identity       ✅
│   ├── storage/
│   │   ├── aws-rds/     # RDS PostgreSQL, encryption, Multi-AZ       ✅
│   │   └── aws-s3/      # S3 bucket, versioning, lifecycle           ✅
│   └── monitoring/
│       ├── aws/         # CloudWatch alarms, SNS topic               ✅
│       └── azure/       # Log Analytics Workspace, Action Group      ✅
│
├── environments/
│   ├── dev/
│   │   ├── aws.tfvars
│   │   ├── azure.tfvars
│   │   ├── gcp.tfvars
│   │   └── backend-*.hcl.example
│   ├── staging/         (same structure)
│   └── prod/            (same structure)
│
└── .github/
    └── workflows/
        └── terraform.yml   # fmt → validate → plan (PR) → apply (main)
```

---

## 🔐 Authentication (no secrets in code)

### Local development

```bash
# AWS — profile or env vars
export AWS_PROFILE=my-profile
# or
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# Azure — env vars (Service Principal)
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."
export ARM_SUBSCRIPTION_ID="..."
# or just: az login

# GCP — Application Default Credentials (keyless, preferred)
gcloud auth application-default login
```

### CI/CD (keyless — no static credentials)

All three clouds use **OIDC / Workload Identity Federation** in GitHub Actions — no long-lived keys stored in secrets:

| Cloud | Method |
|-------|--------|
| AWS   | OIDC → `aws-actions/configure-aws-credentials` |
| Azure | OIDC → `azure/login` (Workload Identity Federation) |
| GCP   | Workload Identity Federation → `google-github-actions/auth` |


### Operational requirements (staging/prod)

- **GitHub Environments approvals:** create `staging` and `prod` environments in GitHub and enable **Required reviewers**. The workflow uses `environment: staging|prod` so approvals are enforced before apply.
- **Self-hosted runner for private clusters:** if the Kubernetes API endpoint is private-only (EKS/AKS/GKE), GitHub-hosted runners cannot reach it. Use a `self-hosted` runner inside the target network (VPC/VNet) for apply and post-apply hardening.


---

## 🚀 Usage

### 1. Remote state (recommended)

Copy the backend example and fill in your bucket/container names:

```bash
cp environments/dev/backend-aws.hcl.example environments/dev/backend-aws.hcl
# edit the file, then:
terraform init -backend-config=../environments/dev/backend-aws.hcl
```

The `.gitignore` excludes all `backend-*.hcl` files (only `.example` versions are committed).

### 2. Deploy

```bash
# AWS
cd aws
terraform init -backend-config=../environments/dev/backend-aws.hcl
terraform plan  -var-file="../environments/dev/aws.tfvars"
terraform apply -var-file="../environments/dev/aws.tfvars"

# Azure
cd ../azure
terraform init -backend-config=../environments/dev/backend-azure.hcl
terraform plan  -var-file="../environments/dev/azure.tfvars"
terraform apply -var-file="../environments/dev/azure.tfvars"

# GCP
cd ../gcp
terraform init -backend-config=../environments/dev/backend-gcp.hcl
terraform plan  -var-file="../environments/dev/gcp.tfvars"
terraform apply -var-file="../environments/dev/gcp.tfvars"
```

### 3. Pre-requisites for Azure

The Azure `main.tf` reads a DB password from Key Vault. Before the first apply, create the secret manually (one-time):

```bash
az keyvault secret set \
  --vault-name "<project>-<env>-kv" \
  --name "postgres-admin-password" \
  --value "<strong-password>"
```

### 4. Pre-requisites for GCP

Terraform generates a strong DB password and stores it in **Secret Manager** automatically.
No manual secret creation is needed.

---

## 🔄 CI/CD — GitHub Actions

The workflow runs on every push/PR touching Terraform files:

```
fmt → validate + tflint + tfsec + checkov → plan (PR)
```

Apply is supported in two modes:

- **Auto-apply to dev** on push to `main`
- **Manual apply via workflow_dispatch** for any environment (recommended for staging/prod with GitHub Environment approvals)

Optional: enable **post-apply Kubernetes hardening** (`k8s/hardening`) using the `enable_post_hardening` input.

### Required repository secrets

**AWS**
```
AWS_ROLE_TO_ASSUME          # IAM role ARN for OIDC
AWS_REGION
AWS_TFSTATE_BUCKET
AWS_TFSTATE_REGION
AWS_TFSTATE_DYNAMODB_TABLE
```

**Azure**
```
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_TFSTATE_RESOURCE_GROUP
AZURE_TFSTATE_STORAGE_ACCOUNT
AZURE_TFSTATE_CONTAINER
```

**GCP**
```
GCP_WORKLOAD_IDENTITY_PROVIDER
GCP_SERVICE_ACCOUNT
GCP_TFSTATE_BUCKET
```

---

## 🌍 Environment differences (prod vs non-prod)

The same code handles all environments. Key prod/non-prod differences:

| Resource | dev/staging | prod |
|----------|-------------|------|
| NAT Gateway | single (cost saving) | one per AZ |
| RDS / Cloud SQL | smallest tier, no Multi-AZ | larger tier, Multi-AZ/Regional |
| RDS backup retention | 7 days | 30 days |
| Deletion protection | disabled | enabled |
| Azure Blob replication | LRS | GRS |
| Azure DB HA | disabled | ZoneRedundant |
| GKE availability | ZONAL | REGIONAL |
| Log retention | 14–30 days | 90 days |

---

## 🔗 Related projects

- [saga-pattern-architecture](../saga-pattern-architecture) — Saga orchestration in Node.js/TypeScript
- [microservices-ddd-kafka](../microservices-ddd-kafka) — DDD + Kafka + Outbox pattern
