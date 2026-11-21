# Identidad del pipeline en el clúster. Reemplaza el kubeconfig de
# administrador que propone la guía: si alguien roba la credencial de
# Jenkins, solo puede tocar el namespace de la app.
resource "kubernetes_service_account_v1" "jenkins_deployer" {
  metadata {
    name      = "jenkins-deployer"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  automount_service_account_token = false
}

# Lo que necesitan apply, set image, rollout status y rollout undo.
resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = "taskapi-deployer"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["services", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = "taskapi-deployer"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.jenkins_deployer.metadata[0].name
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
}

# El Namespace es un recurso de clúster: un Role no lo cubre. Este
# ClusterRole deja leer y actualizar SOLO devops-project, para que
# `kubectl apply -f k8s/namespace.yaml` funcione con el deployer. No
# permite crear ni borrar namespaces.
resource "kubernetes_cluster_role_v1" "namespace_apply" {
  metadata {
    name = "taskapi-namespace-apply"
  }
  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = [var.app_namespace]
    verbs          = ["get", "patch", "update"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "namespace_apply" {
  metadata {
    name = "taskapi-namespace-apply"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.namespace_apply.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.jenkins_deployer.metadata[0].name
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }
}

# Token de larga duración para el ServiceAccount (desde 1.24 ya no se crea
# solo). Se revoca borrando este Secret: terraform apply genera uno nuevo.
resource "kubernetes_secret_v1" "jenkins_deployer_token" {
  metadata {
    name      = "jenkins-deployer-token"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.jenkins_deployer.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# Kubeconfig del deployer, listo para subirlo a Jenkins como credencial
# "Secret file". Se escribe en out/, que está en .gitignore.
resource "local_sensitive_file" "jenkins_kubeconfig" {
  filename        = "${path.module}/out/jenkins-kubeconfig.yaml"
  file_permission = "0600"
  content = templatefile("${path.module}/templates/kubeconfig.tftpl", {
    server          = var.jenkins_api_server
    tls_server_name = var.jenkins_tls_server_name
    ca_data         = base64encode(kubernetes_secret_v1.jenkins_deployer_token.data["ca.crt"])
    token           = kubernetes_secret_v1.jenkins_deployer_token.data["token"]
    namespace       = var.app_namespace
  })
}
