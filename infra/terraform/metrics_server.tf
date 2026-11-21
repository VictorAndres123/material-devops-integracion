# metrics-server por Helm: reemplaza la instalación manual con kubectl de
# la Fase 1, así la plataforma completa se recrea con un solo apply.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  # El kubelet de Docker Desktop usa un certificado autofirmado.
  values = [yamlencode({
    args = ["--kubelet-insecure-tls"]
  })]

  wait    = true
  timeout = 300
}
