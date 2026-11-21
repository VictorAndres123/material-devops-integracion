# Semana 3 · Matriz rúbrica → evidencia

Cada fila dice qué pide el nivel 5, cómo se piensa cumplir en un entorno local y qué evidencia lo demuestra. Las fases son las del plan de trabajo.

## Requisitos obligatorios del enunciado

| Requisito | Evidencia | Fase |
|---|---|---|
| 5 manifiestos en `k8s/` | Archivos en el repo + `kubectl get all -n devops-project` | 1 |
| Pipeline de 5 stages en verde | Captura de la vista de stages en Jenkins | 4–5 |
| JUnit 11/11 publicado | Captura de "Test Result" del build | 4–5 |
| Imagen `:N` y `:latest` en Docker Hub | Captura de la pestaña Tags con el mismo digest | 5 |
| 2 pods Running | `kubectl get pods -n devops-project` | 1, 5 |
| `/health` y `/docs` respondiendo | `curl.exe http://localhost/health` + captura de Swagger | 1, 5 |

## Criterios de la rúbrica

| Criterio | Qué pide el nivel 5 | Cómo se cumple | Evidencia | Fase |
|---|---|---|---|---|
| **Implementación IaC & K8s** | Despliegue multizona, alta disponibilidad real y optimización de recursos | Terraform para la plataforma (namespace, quota, LimitRange, RBAC, NetworkPolicy, releases de Helm). Deployment con RollingUpdate `maxUnavailable: 0`, startup/liveness/readiness probes, PDB, anti-afinidad o `topologySpreadConstraints`. HPA de 2 a 5 con metrics-server. Requests y limits medidos con datos reales de Grafana. Multizona con kind multinodo y nodos etiquetados por zona, si Docker Desktop lo permite. | `terraform plan` sin cambios; `kubectl get pdb,hpa,quota`; prueba de borrar un pod sin errores; HPA escalando bajo carga; pods repartidos por zona (`kubectl get pods -o wide`) | 1, 2 |
| **Monitoreo & Seguridad** | Observabilidad total con dashboards predictivos y seguridad integrada (shift left) en todo el ciclo | kube-prometheus-stack + Loki. `/metrics` en la API, ServiceMonitor, dashboards como código (RED, Kubernetes, logs, panel con `predict_linear()`). PrometheusRule con 5 alertas. En el pipeline: gitleaks, bandit, pip-audit, checkov sobre k8s/ y Terraform, Trivy sobre la imagen, SBOM, smoke test y rollback automático. ServiceAccount con RBAC mínimo y TLS verificado. | Capturas de dashboards con datos, alerta en firing, reportes de seguridad archivados en Jenkins, build bloqueado por una dependencia vulnerable | 3, 4 |
| **Calidad audiovisual** | Producción de alta gama, narrativa técnica impecable, demos en vivo fluidas | Guion con tiempos y storyboard. Demo en vivo: push → pipeline → rollout con bucle de cero errores → HPA → Grafana → alerta → bloqueo de seguridad. Subtítulos .srt, gráficos CORHUILA, citas APA en pantalla. | Video final + archivo .srt | 7 |
| **Documentación técnica** | Nivel senior: exhaustiva, con análisis prospectivo y guías de replicabilidad | PDF en plantilla institucional con diagramas C4, despliegue, pipeline, observabilidad y seguridad. ADRs con alternativas, fragmentos de código, resultados reales, limitaciones, análisis prospectivo y guía de replicación desde cero. | PDF final | 6 |
| **APA & rigor académico** | Integración perfecta de fuentes, citas impecables, bibliografía de vanguardia | 12 a 18 referencias verificadas, la mayoría desde 2020, con al menos 4 artículos revisados por pares con DOI. Cada cita aparece en la lista y al revés. | Sección de referencias del PDF + citas en el video | 8 |

## Lo que se va a simular y hay que decir en el informe

- Las zonas son etiquetas en nodos de un solo equipo, no zonas físicas.
- El LoadBalancer de Docker Desktop publica en `localhost`; no hay balanceador real.
- El estado de Terraform es local.
- Las alertas llegan a Alertmanager, pero no salen a un canal externo (correo o Slack), salvo que se configure un webhook de prueba.
