# Fase 2 · Infraestructura como código con Terraform

## Qué maneja Terraform y qué no

| Capa | Dueño | Por qué |
|---|---|---|
| Namespace `devops-project` | `k8s/namespace.yaml` (pipeline) | El enunciado lo exige como manifiesto. Terraform solo lo lee con un `data`. |
| ResourceQuota y LimitRange | Terraform | Son reglas de la plataforma, no de la app. No cambian con cada build. |
| NetworkPolicy | Terraform | Igual. Docker Desktop no la hace cumplir (ver H14 en la auditoría). |
| ServiceAccount, Role, ClusterRole y bindings del deployer | Terraform | La identidad del pipeline no debería poder modificarse a sí misma desde el pipeline. |
| Kubeconfig de Jenkins | Terraform (archivo en `out/`, fuera de git) | Se genera a partir del token del ServiceAccount. |
| metrics-server | Terraform (Helm) | Reemplaza la instalación manual de la Fase 1. |
| Deployment, Service, ConfigMap, HPA y PDB | Pipeline (`kubectl apply`) | Cambian con cada build. Si los manejara Terraform, cada deploy pasaría por un `terraform apply` con el estado local de la laptop. |

Esta separación (plataforma con Terraform, aplicación con el pipeline) es la misma que se usa en equipos con un grupo de plataforma y varios equipos de producto. Va como ADR en el informe.

## Por qué el estado es local

Un solo operador, un solo clúster y ninguna nube. Un backend remoto (Azure Storage, S3 con bloqueo o Terraform Cloud) agrega una cuenta y credenciales que el curso no pide. En `versions.tf` queda comentado cómo sería con `azurerm`. El riesgo de perder el estado es bajo porque todo se puede reimportar o recrear con un `apply`.

## Archivos

```
infra/terraform/
├── versions.tf         # Terraform >= 1.6, providers fijados
├── providers.tf        # kubeconfig y contexto docker-desktop
├── variables.tf
├── namespace.tf        # data source del namespace de la app
├── quotas.tf           # ResourceQuota + LimitRange (cálculo en el comentario)
├── network.tf          # default-deny + permitir 8000
├── rbac.tf             # jenkins-deployer, Role, ClusterRole acotado, token, kubeconfig
├── metrics_server.tf   # Helm release
├── outputs.tf
├── templates/kubeconfig.tftpl
├── .tflint.hcl
└── .gitignore          # estado, .terraform/ y out/ fuera de git
```

## Comandos (PowerShell)

```powershell
# 0. Instalar Terraform si no lo tienes (abre otra terminal después para que tome el PATH)
winget install --id Hashicorp.Terraform -e
terraform version

# 1. Quitar el metrics-server instalado a mano en la Fase 1 (Helm no puede adoptarlo)
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 2. Terraform
cd infra\terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out fase2.tfplan
terraform apply fase2.tfplan

# 3. Idempotencia: no debe proponer cambios
terraform plan -detailed-exitcode
#   Código de salida 0 = sin cambios
echo $LASTEXITCODE

# 4. Verificar en el clúster
kubectl get resourcequota,limitrange,networkpolicy,sa,role,rolebinding -n devops-project
kubectl describe resourcequota taskapi-quota -n devops-project
kubectl get hpa -n devops-project
kubectl auth can-i patch deployments -n devops-project --as=system:serviceaccount:devops-project:jenkins-deployer
kubectl auth can-i delete namespaces --as=system:serviceaccount:devops-project:jenkins-deployer
kubectl auth can-i get secrets -n kube-system --as=system:serviceaccount:devops-project:jenkins-deployer

# 5. Escaneo de seguridad de IaC con Trivy (sin instalar nada: corre en Docker)
cd ..\..
# trivy config acepta un solo directorio por ejecución
docker run --rm -v "${PWD}:/src" aquasec/trivy:latest config --severity HIGH,CRITICAL /src/infra/terraform
docker run --rm -v "${PWD}:/src" aquasec/trivy:latest config --severity HIGH,CRITICAL /src/k8s
```

Resultado esperado del paso 4: `yes`, `no`, `no`. El deployer puede desplegar la app, pero no puede borrar namespaces ni leer secretos de otros namespaces.

## Prueba de destruir y recrear

```powershell
cd infra\terraform
terraform destroy -auto-approve
kubectl get resourcequota,sa -n devops-project   # ya no están
terraform apply -auto-approve
terraform plan -detailed-exitcode; echo $LASTEXITCODE   # 0
```

Durante el destroy el HPA vuelve a `<unknown>` porque metrics-server desaparece. La app sigue respondiendo.

## ¿El contenedor de Jenkins llega al API server?

Esto define el valor de `jenkins_api_server` en la Fase 4:

```powershell
docker exec jenkins getent hosts kubernetes.docker.internal
docker exec jenkins getent hosts host.docker.internal
```

- Si el primero devuelve una IP, se deja el valor por defecto y se conserva la verificación TLS sin cambios.
- Si solo resuelve el segundo: `terraform apply -var="jenkins_api_server=https://host.docker.internal:6443" -var="jenkins_tls_server_name=kubernetes.docker.internal"`. Kubectl se conecta a `host.docker.internal` pero valida el certificado contra `kubernetes.docker.internal`, que sí está en sus SAN. Así no hace falta `insecure-skip-tls-verify`.

## Evidencias de esta fase

1. `terraform apply` terminado con "Apply complete! Resources: N added"
2. `terraform plan -detailed-exitcode` con código 0
3. `kubectl describe resourcequota` mostrando lo usado frente al límite
4. Los tres `kubectl auth can-i` (yes, no, no)
5. Reporte de Trivy sobre IaC (los hallazgos se discuten en el informe)
6. HPA de nuevo con porcentaje después de pasar metrics-server a Helm
