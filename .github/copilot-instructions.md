# Copilot Instructions: Modern GitOps Stack - ArgoCD Module

## Project Overview

This is a **dual-module Terraform project** for deploying Argo CD as part of the Modern GitOps Stack. It provides two distinct deployment strategies:

1. **Bootstrap module** (`bootstrap/`): Deploys Argo CD via Helm provider for initial cluster setup
2. **Main module** (root): Manages Argo CD using the ArgoCD Terraform provider for ongoing operations

## Critical Architecture Patterns

### Bootstrap vs Main Module Pattern

- **Never deploy both simultaneously** - bootstrap is for initial deployment only
- Bootstrap uses `helm_release` resource, main uses `argocd_application` resource
- Bootstrap outputs (`argocd_server_secretkey`, `argocd_accounts_pipeline_tokens`) are **required inputs** for the main module
- Transition requires careful state management to avoid conflicts

### Dependency Chain Management

The main module has strict dependency requirements enforced via `dependency_ids`:

```terraform
dependency_ids = {
  argocd                = module.argocd_bootstrap.id
  traefik               = module.traefik.id
  cert-manager          = module.cert-manager.id
  oidc                  = module.oidc.id
  kube-prometheus-stack = module.kube-prometheus-stack.id
}
```

### Custom Plugin Architecture

Two embedded Config Management Plugins (CMPs):

1. **kustomized-helm**: Combines Helm + Kustomize processing
2. **helmfile-cmp**: Supports Helmfile with SOPS encryption

Plugin configurations are defined in `locals.tf` as `repo_server_extra_containers` and deployed via `extraObjects`.

## Key Configuration Patterns

### Variable Validation & Defaults

- Use `optional()` extensively for complex object variables (see `resources`, `high_availability`)
- Bootstrap requires first project to be `destination_cluster = "in-cluster"`
- Resource requests are **cumulative** for repo-server containers due to plugin architecture

### YAML Deep Merging

All Helm values use `utils_deep_merge_yaml` for layered configuration:

```terraform
data "utils_deep_merge_yaml" "values" {
  input = [for i in concat(local.helm_values, var.helm_values) : yamlencode(i)]
  append_list = true
}
```

### JWT Token Management

- Bootstrap generates `random_password` for server secret key
- Main module creates JWT tokens for extra accounts using `jwt_hashed_token` resource
- All tokens reference the same server secret key for consistency

## Development Workflows

### Local Testing Commands

```bash
# Validate Terraform syntax
terraform fmt -check -recursive
terraform validate

# Run linters (uses remote workflow)
# Check .github/workflows/linters.yaml for CI pipeline

# Update documentation
terraform-docs markdown table --output-file README.md .
terraform-docs markdown table --output-file bootstrap/README.md bootstrap/
```

### Chart Version Management

- Chart versions locked in `chart-version.yaml` and `charts/argocd/Chart.lock`
- Version bumps trigger automatic documentation updates via GitHub Actions
- Use `chart-update.yaml` workflow for Helm chart synchronization

### Common Troubleshooting Patterns

#### Connection Errors During Apply

```bash
# If argocd_application resource gets tainted during deployment
terraform untaint module.argocd.argocd_application.this
```

#### High Availability Mode

- Requires **minimum 3 worker nodes** for Redis HA
- Autoscaling only applies to `server` and `repo_server` components
- HA mode changes Redis chart from standalone to `redis-ha` subchart

## File Organization Logic

- `locals.tf`: Complex Helm values construction and plugin definitions
- `variables.tf`: Extensive use of optional object patterns for flexible configuration
- `bootstrap/`: Separate Terraform state for initial deployment
- `charts/argocd/`: Embedded Helm chart to avoid external version drift

## Integration Points

### External Dependencies

- **Traefik**: Required for ingress configuration
- **cert-manager**: SSL certificate management
- **kube-prometheus-stack**: ServiceMonitor CRDs
- **OIDC providers**: Authentication integration

### SOPS Integration

Configure via `helmfile_cmp_env_variables` and cloud provider service accounts:

- AWS: `repo_server_iam_role_arn`
- Azure: `repo_server_azure_workload_identity_clientid` or `repo_server_aadpodidbinding`

## Security Considerations

- Pipeline tokens marked as `sensitive = true`
- RBAC policy defaults include `modern-gitops-stack-admins` group
- Admin user disabled by default in main module (`admin_enabled = false`)
- TLS termination handled at Traefik level (`server.insecure = true`)
