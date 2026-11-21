# Versiones fijadas: el mismo código produce el mismo plan en cualquier equipo.
# .terraform.lock.hcl (se genera con terraform init) va al repo.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Estado local a propósito: un solo operador y un clúster de laptop.
  # En un equipo de varias personas iría en un backend remoto con bloqueo,
  # por ejemplo:
  # backend "azurerm" { resource_group_name = "...", storage_account_name = "...",
  #                     container_name = "tfstate", key = "devops-taskapi.tfstate" }
}
