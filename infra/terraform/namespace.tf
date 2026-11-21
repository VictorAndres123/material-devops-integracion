# El namespace lo maneja k8s/namespace.yaml (requisito del enunciado y lo
# aplica el pipeline). Terraform solo lo lee: si no existe, el plan falla
# con un mensaje claro en vez de crear un duplicado con otro dueño.
data "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
  }
}
