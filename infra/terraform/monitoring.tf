# Observabilidad: métricas (Prometheus), alertas (Alertmanager), dashboards
# (Grafana) y logs (Loki + Alloy). Todo en el namespace monitoring y con
# valores pensados para los ~7,5 GB que tiene Docker Desktop.

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      project = "devops-taskapi"
    }
  }
}

# Contraseña de Grafana generada, no escrita en el repo.
# Se lee con: terraform output -raw grafana_admin_password
resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version

  values = [
    file("${path.module}/monitoring/kps-values.yaml"),
    yamlencode({
      grafana = {
        service = {
          type = "LoadBalancer"
          port = var.grafana_port
        }
      }
      # Alertas propias de la API, versionadas en un archivo aparte.
      additionalPrometheusRulesMap = {
        taskapi = yamldecode(file("${path.module}/monitoring/taskapi-rules.yaml"))
      }
    }),
  ]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = random_password.grafana_admin.result
  }

  wait    = true
  timeout = 900
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version

  values = [file("${path.module}/monitoring/loki-values.yaml")]

  wait    = true
  timeout = 600
}

resource "helm_release" "alloy" {
  name       = "alloy"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version

  values = [file("${path.module}/monitoring/alloy-values.yaml")]

  # 10 minutos: la primera instalación descarga ~240 MB de imágenes (Alloy y
  # su config-reloader) y en la laptop eso tomó más de 5.
  wait       = true
  timeout    = 600
  depends_on = [helm_release.loki]
}

# Dashboard de la API como código: el sidecar de Grafana carga cualquier
# ConfigMap con la etiqueta grafana_dashboard=1.
resource "kubernetes_config_map_v1" "taskapi_dashboard" {
  metadata {
    name      = "taskapi-dashboard"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "taskapi.json" = file("${path.module}/dashboards/taskapi.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
