# Kubernetes hardening (post-apply)

This directory contains portable baseline hardening resources you can apply *after* provisioning the clusters.

## What's included

- **Namespaces** with Pod Security Admission (PSA) labels
- **NetworkPolicies**: default-deny + allow DNS + allow internal RFC1918 egress
- **Kyverno** (PSP replacement): policies to deny privileged pods and require `runAsNonRoot`

## How it's applied

- In CI/CD, this is applied only when `enable_post_hardening=true`.
- If your cluster API endpoint is private-only, you must run CI on a runner with private network connectivity (e.g., a self-hosted runner inside the VPC/VNet).

