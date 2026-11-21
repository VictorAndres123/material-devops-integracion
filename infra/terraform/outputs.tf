output "jenkins_kubeconfig_path" {
  description = "Archivo a subir en Jenkins como credencial Secret file (ID: k8s-deployer-kubeconfig)."
  value       = local_sensitive_file.jenkins_kubeconfig.filename
}

output "deployer_service_account" {
  value = "${var.app_namespace}/${kubernetes_service_account_v1.jenkins_deployer.metadata[0].name}"
}

output "resource_quota" {
  value = kubernetes_resource_quota_v1.app.spec[0].hard
}

output "grafana_url" {
  value = "http://localhost:${var.grafana_port}  (usuario: admin)"
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}
