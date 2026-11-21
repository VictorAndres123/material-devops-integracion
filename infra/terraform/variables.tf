variable "kubeconfig_path" {
  description = "Kubeconfig del operador (el de Docker Desktop)."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto de kubectl donde se aplica la plataforma."
  type        = string
  default     = "docker-desktop"
}

variable "app_namespace" {
  description = "Namespace de la aplicación. Lo crea k8s/namespace.yaml, como pide el enunciado."
  type        = string
  default     = "devops-project"
}

variable "jenkins_api_server" {
  description = "URL del API server tal como la ve el contenedor de Jenkins."
  type        = string
  default     = "https://kubernetes.docker.internal:6443"
}

variable "jenkins_tls_server_name" {
  description = "Nombre a validar en el certificado si jenkins_api_server usa otro host (p. ej. host.docker.internal). Vacío = no se usa."
  type        = string
  default     = ""
}

variable "metrics_server_chart_version" {
  description = "Versión del chart de metrics-server."
  type        = string
  default     = "3.12.2"
}
