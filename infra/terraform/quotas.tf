# Techo de recursos del namespace. Se calcula sobre el peor caso:
# 5 pods (maxReplicas del HPA) + 1 de surge en un rollout = 6 pods.
#   requests: 6 x 100m = 600m CPU, 6 x 128Mi = 768Mi
#   limits:   6 x 250m = 1500m CPU, 6 x 256Mi = 1536Mi
resource "kubernetes_resource_quota_v1" "app" {
  metadata {
    name      = "taskapi-quota"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "1"
      "requests.memory" = "1Gi"
      "limits.cpu"      = "2"
      "limits.memory"   = "2Gi"
      "pods"            = "10"
    }
  }
}

# Valores por defecto y máximos por contenedor: un pod sin requests/limits
# no rompe la cuota ni se come el nodo.
resource "kubernetes_limit_range_v1" "app" {
  metadata {
    name      = "taskapi-limits"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
      default = {
        cpu    = "250m"
        memory = "256Mi"
      }
      max = {
        cpu    = "500m"
        memory = "512Mi"
      }
    }
  }
}
