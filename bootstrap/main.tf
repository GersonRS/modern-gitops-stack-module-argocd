resource "random_password" "argocd_server_secretkey" {
  length  = 32
  special = false
}

# jwt token for `pipeline` account
resource "jwt_hashed_token" "argocd" {
  algorithm   = "HS256"
  secret      = random_password.argocd_server_secretkey.result
  claims_json = jsonencode(local.jwt_token_payload)
}

resource "time_static" "iat" {}

resource "random_uuid" "jti" {}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = local.argocd_chart.repository
  chart      = local.argocd_chart.name
  version    = local.argocd_chart.version

  namespace         = "argocd"
  dependency_update = true
  create_namespace  = true
  timeout           = 10800
  values            = [data.utils_deep_merge_yaml.values.output]

  lifecycle {
    ignore_changes = all
  }
}

resource "argocd_project" "modern_gitops_stack_applications" {
  for_each = var.argocd_projects

  metadata {
    name      = each.key
    namespace = "argocd"
  }

  spec {
    description  = "Modern GitOps Stack applications in cluster ${each.value.destination_cluster}"
    source_repos = each.value.allowed_source_repos

    dynamic "destination" {
      for_each = each.value.allowed_namespaces

      content {
        name      = each.value.destination_cluster
        namespace = destination.value
      }
    }

    orphaned_resources {
      warn = true
    }

    cluster_resource_whitelist {
      group = "*"
      kind  = "*"
    }
  }
}

data "utils_deep_merge_yaml" "values" {
  input       = [for i in concat([local.helm_values.0.argo-cd], [var.helm_values.0.argo-cd]) : yamlencode(i)]
  append_list = true
}

resource "null_resource" "this" {
  depends_on = [
    resource.helm_release.argocd,
    resource.random_password.argocd_server_secretkey,
    resource.argocd_project.modern_gitops_stack_applications,
  ]
}
