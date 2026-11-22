# Fase 3 · Observabilidad: métricas, logs, dashboards y alertas

## Qué se agregó

| Pieza | Dónde | Para qué |
|---|---|---|
| `GET /metrics` | `app/main.py` (prometheus-fastapi-instrumentator 8.1.0) | Peticiones por ruta, método y código; latencia en histograma |
| kube-prometheus-stack 93.6.1 | `infra/terraform/monitoring.tf` | Prometheus, Alertmanager, Grafana, kube-state-metrics y Prometheus Operator |
| Loki 21.4.3 (grafana-community) | ídem | Almacena los logs, modo monolítico en disco |
| Alloy 1.16.0 | ídem | Lee los logs de los pods de `devops-project` y los manda a Loki |
| ServiceMonitor `taskapi` | `monitoring/kps-values.yaml` | Prometheus raspa `taskapi-service:http/metrics` cada 15 s |
| 8 alertas | `monitoring/taskapi-rules.yaml` | Disponibilidad, tráfico y capacidad, con 2 predictivas |
| Dashboard "DevOps Task Manager API" | `dashboards/taskapi.json` | 19 paneles: estado, RED, escalado, predicción y logs |
| Prueba de carga | `loadtest/k6-hpa.js` | Lleva el HPA de 2 a 5 réplicas |

Todo lo de monitoreo es código: si se borra el namespace `monitoring`, un `terraform apply` lo recrea igual, con el dashboard y las alertas.

## Decisiones

**Por qué estas versiones.** Se verificaron el 20/11/2026 contra los tags de cada repositorio. El chart OSS de Loki se mudó en marzo de 2026 de `grafana/helm-charts` a `grafana-community/helm-charts`; el antiguo ahora es solo para Grafana Enterprise Logs. Promtail está en fin de vida, así que el agente de logs es Alloy.

**Qué se apagó y por qué.** etcd, scheduler, controller-manager y kube-proxy no son accesibles para Prometheus en Docker Desktop. Si se dejan activos, sus alertas `TargetDown` quedan siempre disparadas y tapan las que importan. node-exporter necesita montar la raíz del host y eso falla en Docker Desktop; las métricas de pods salen de cAdvisor (kubelet) y kube-state-metrics. Las cachés memcached, el canary y el gateway de Loki son pods extra que en un solo nodo no aportan.

**Recursos.** Requests y límites de memoria en cada componente para que el stack quepa en los ~7,5 GB de Docker Desktop. Prometheus guarda 24 h.

**Mínimo privilegio también en observabilidad.** Alloy usa un Role solo en `devops-project`, no un ClusterRole: no puede leer logs de otros namespaces. La contraseña de Grafana la genera Terraform (`random_password`) y no está en el repo.

**Alertas predictivas.** `predict_linear` extrapola la tendencia de 30 minutos. `TaskApiMemoriaSeAgotaraPronto` avisa si la memoria llegaría al límite en una hora (antes de un OOMKilled). `TaskApiCpuSaturacionPrevista` avisa si la CPU llegaría al 90 % del límite en 15 minutos. Son las que justifican hablar de "dashboards predictivos": no muestran solo lo que pasó, sino hacia dónde va.

**Latencia con el histograma de alta resolución.** El instrumentador expone dos histogramas. El que tiene etiqueta de ruta solo tiene los buckets 0,1, 0,5 y 1 s, muy gruesos para un p95. Las alertas y el panel de latencia usan `http_request_duration_highr_seconds`, que tiene 20 buckets.

## Problemas reales durante la instalación

**Alloy superó el timeout de Helm.** La primera instalación tuvo que descargar unos 240 MB de imágenes (Alloy v1.22.0 y su config-reloader) y tardó más de los 300 s configurados. El pod quedó sano, pero Helm marcó el release como `failed` y Terraform lo dejó *tainted*. Se resolvió con `terraform untaint helm_release.alloy`, para no recrear un recurso que estaba bien, y subiendo el timeout a 600 s.

**cAdvisor en Docker Desktop no publica la etiqueta `container`.** El panel de CPU salía vacío. Prometheus sí raspaba cAdvisor (`up` = 1), pero `container_cpu_usage_seconds_total` solo traía `namespace` y `pod`: en este entorno el uso se reporta por pod. Las consultas del dashboard y las dos alertas predictivas se cambiaron para filtrar por `pod=~"taskapi-.*"` y sumar los límites por pod. Como cada pod tiene un solo contenedor, el resultado es equivalente. En un clúster administrado (EKS, AKS, GKE) las series sí traen `container` y las consultas originales funcionarían.

**Idempotencia.** Después de las correcciones, `terraform plan -detailed-exitcode` devolvió `0` ("No changes"): los 18 recursos de las Fases 2 y 3 coinciden con el código.

## Comandos (PowerShell)

```powershell
cd C:\Users\ESTEBAN\Desktop\material-devops-integracion

# 1. La app con /metrics pasa por el pipeline (pip-audit revisa la librería nueva)
git add app/main.py requirements.txt
git commit -m "feat(app): endpoint /metrics para Prometheus"
git push origin main
# Build Now en Jenkins y esperar el verde

# 2. Infraestructura de monitoreo
git add infra/ loadtest/ docs/
git commit -m "feat(infra): Prometheus, Grafana, Loki y Alloy con alertas y dashboard como código"
cd infra\terraform
terraform init -upgrade
terraform validate
terraform plan -out fase3.tfplan
terraform apply fase3.tfplan          # 5 a 10 minutos la primera vez
terraform output -raw grafana_admin_password
cd ..\..

# 3. Verificar
kubectl get pods -n monitoring
kubectl top pods -n monitoring
curl.exe -s http://localhost/metrics | Select-String http_requests_total | Select-Object -First 5
```

Grafana: http://localhost:3000, usuario `admin` y la contraseña del paso 2. Dashboard: **Dashboards → DevOps Task Manager API**.

Prometheus y Alertmanager no quedan publicados; se abren con port-forward, cada uno en su terminal:

```powershell
kubectl port-forward -n monitoring svc/kps-prometheus 9090:9090      # http://localhost:9090/targets
kubectl port-forward -n monitoring svc/kps-alertmanager 9093:9093    # http://localhost:9093
```

En http://localhost:9090/targets, el target `serviceMonitor/monitoring/kps-taskapi/0` debe aparecer con 2/2 en **UP**.

## Prueba de escalado y alerta

Tres terminales:

```powershell
# Terminal 1: el HPA en vivo
kubectl get hpa -n devops-project -w

# Terminal 2: los pods
kubectl get pods -n devops-project -w

# Terminal 3: la carga (unos 6 minutos)
docker run --rm -v "${PWD}/loadtest:/scripts" grafana/k6 run /scripts/k6-hpa.js
```

Esperado: la CPU pasa el 60 %, el HPA sube a 3, 4 y 5 réplicas, y después de un minuto en 5 se dispara `TaskApiHpaAlMaximo` (Prometheus → Alerts, y Alertmanager). Al terminar la carga, el HPA baja de a un pod por minuto hasta 2.

## Evidencias de esta fase

1. `kubectl get pods -n monitoring` con todo en Running
2. Prometheus → Targets con el ServiceMonitor de taskapi en UP
3. Prometheus → Alerts con las 8 reglas de taskapi cargadas
4. Dashboard en reposo
5. Dashboard durante la carga: peticiones/s, latencia, CPU cruzando el umbral y réplicas subiendo
6. `kubectl get hpa -w` mostrando 2 → 5
7. Alerta `TaskApiHpaAlMaximo` en estado Firing (Prometheus y Alertmanager)
8. Panel de logs con líneas de los pods
9. Resumen final de k6 (peticiones, p95 y `http_req_failed`)
10. `kubectl top pods -n monitoring` (consumo real del stack, para el análisis de recursos)
