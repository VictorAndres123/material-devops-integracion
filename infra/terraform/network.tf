# Todo el tráfico de entrada se niega salvo el que se permite abajo.
# OJO: el Kubernetes de Docker Desktop no trae un CNI que haga cumplir
# NetworkPolicy. Aquí queda declarada y versionada; en un clúster con
# Calico o Cilium (EKS, AKS, GKE) se aplicaría tal cual.
resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_taskapi_http" {
  metadata {
    name      = "allow-taskapi-http"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "taskapi"
      }
    }

    policy_types = ["Ingress"]

    # Solo el puerto de la API. El tráfico del LoadBalancer llega desde el
    # nodo, por eso no se restringe el origen.
    ingress {
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}
