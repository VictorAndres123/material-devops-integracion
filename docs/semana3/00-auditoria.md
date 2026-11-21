# Semana 3 · Auditoría del repositorio antes de Kubernetes

Revisión hecha sobre `main` en el commit `e04d5be` (fix: restaura test_health_check después de la prueba de fallo). Todavía no se ha cambiado código: este documento solo registra cómo está el repo y qué hay que tocar para la Actividad de Aprendizaje 4.

## 1. Estado actual

| Pieza | Estado | Comentario |
|---|---|---|
| API FastAPI (`app/`) | Lista | `/health` ya existe y sirve para las probes. 11 tests en `tests/test_tasks.py`. |
| `Dockerfile` de la app | Bien encaminado | Multietapa, `python:3.12-slim`, usuario `appuser`, BD en `/app/data`. |
| `Jenkinsfile` | 4 stages | Checkout, Test (con cobertura mínima de 85 %), Build (etiquetas OCI), Push. Tiene `timeout`, `disableConcurrentBuilds`, `buildDiscarder`. |
| `jenkins/Dockerfile` | Sin kubectl | Trae Docker CLI, Python 3 y gosu. |
| `jenkins/docker-compose.yml` | Sin kubeconfig | Monta `jenkins_home` y el socket de Docker. |
| `k8s/` | No existe | Hay que crear los cinco manifiestos. |
| `docs/` | No existía | Se crea con esta auditoría. |
| GitHub Actions | Existe | `verificacion.yml` repite la verificación de la Semana 1 (tests en 3.10 y 3.12, imagen, seed, compose). |

## 2. Hallazgos que afectan la Semana 3

**H1. `runAsNonRoot` va a fallar con el Dockerfile actual.** La imagen declara `USER appuser` (un nombre). Kubernetes no puede confirmar que un nombre de usuario no sea root, así que con `runAsNonRoot: true` el pod no arranca y queda en `CreateContainerConfigError`. Hay dos salidas: poner `USER 1000` en el Dockerfile o fijar `runAsUser: 1000` en el `securityContext`. Prefiero la primera porque deja la imagen correcta en cualquier orquestador.

**H2. La imagen de producción lleva herramientas de test.** `requirements.txt` incluye `pytest` y `httpx`, y el Dockerfile instala ese archivo. Eso suma peso y superficie de ataque sin aportar nada en runtime. Se mueven a `requirements-dev.txt`. El impacto en la Semana 2 es mínimo porque el stage Test ya instala `requirements-dev.txt`, pero hay que ajustar el workflow de GitHub Actions, que hoy instala `requirements.txt` para correr pytest.

**H3. Es probable que pip-audit marque FastAPI 0.115.0.** Esa versión arrastra una Starlette anterior a 0.40, y las versiones viejas de Starlette tienen avisos de seguridad publicados. Hay que confirmarlo corriendo `pip-audit`. Si sale, tiene dos usos: es un hallazgo real para el informe y sirve de demostración de que el pipeline bloquea dependencias vulnerables. Después se actualiza la versión.

**H4. El socket de Docker queda abierto a todo el contenedor.** `docker-entrypoint.sh` hace `chmod 666 /var/run/docker.sock`. Quien tenga shell en el contenedor Jenkins controla el daemon de Docker Desktop, y eso equivale a ser administrador del host. En un entorno local de aprendizaje es aceptable, pero va al informe como riesgo con su alternativa: agentes efímeros, Kaniko o BuildKit rootless.

**H5. El kubeconfig que propone la guía es de administrador.** La guía monta `~/.kube` completo dentro de Jenkins y apaga la verificación TLS con `insecure-skip-tls-verify`. El pipeline quedaría con permisos totales sobre el clúster. Para el nivel 4–5 de seguridad conviene un ServiceAccount `jenkins-deployer` limitado al namespace y conservar la verificación del certificado con `tls-server-name`.

**H6. SQLite con `emptyDir` y 2 réplicas.** Cada pod tiene su propia base. Una tarea creada en un pod no aparece si la siguiente petición cae en el otro, y todo se borra en cada rollout. El enunciado lo pide así a propósito, así que no se cambia, pero se documenta como limitación y se explica cómo se resolvería (PostgreSQL con PVC o una base gestionada).

**H7. metrics-server.** La guía dice que Docker Desktop ya lo trae. No es así en la instalación por defecto, y sin él el HPA muestra `<unknown>/60%`. Hay que instalarlo con `--kubelet-insecure-tls`.

**H8. Orden de `kubectl apply -f k8s/`.** Se aplica en orden alfabético y `configmap.yaml` va antes que `namespace.yaml`. En un clúster limpio el primer apply falla si no se aplica antes el namespace. La guía lo resuelve con dos comandos; se mantiene igual.

**H9. Imagen base sin fijar por digest.** `python:3.12-slim` cambia con el tiempo. Para builds reproducibles y para que el escaneo de Trivy sea comparable entre builds, conviene fijarla con `@sha256:...`.

**H10. `post` del Jenkinsfile.** Hoy borra el tag `:N` local después del push. Eso no afecta a Kubernetes, que descarga desde Docker Hub. Se conserva.

**H11. Numeración.** El enunciado habla de "pasos 22–24", pero la guía numera de 16 a 22. Se sigue la guía.

**H12. Lo que pide la rúbrica y no pide el enunciado.** El enunciado se limita a Kubernetes y al pipeline. La rúbrica además califica Terraform, monitoreo con alertas, DevSecOps, un video, un PDF con diagramas y APA 7. Todo eso hay que construirlo aparte de la guía.

**H13. `kubectl apply` y `kubectl set image` se pisan.** El Deployment declara `:latest` y el pipeline luego cambia la imagen a `:N`. En cada build, `kubectl apply -f k8s/` devuelve la imagen a `:latest` (un rollout) y `kubectl set image` la pone en `:N` (otro rollout). Con `maxUnavailable: 0` no se corta el servicio, pero cada deploy reinicia los pods dos veces. El enunciado exige los dos comandos, así que se conservan. En la Fase 4 el apply del Deployment se hace con la imagen ya reemplazada por `:N`, y así `set image` queda como confirmación sin segundo rollout.

**H14. NetworkPolicy en Docker Desktop.** El Kubernetes de Docker Desktop no trae un CNI que haga cumplir NetworkPolicy. La política se puede crear y validar, pero no bloquea tráfico en este clúster. Se documenta así, sin presentarla como un control activo.

## 3. Riesgos

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| RAM insuficiente con Prometheus, Grafana y Loki en Docker Desktop | Alta | Pods en `Pending` u `OOMKilled` | Valores livianos en Helm, retención corta, 8 GB o más para Docker Desktop |
| El pipeline de la Semana 2 se rompe al endurecer la imagen | Media | Pierde evidencia ya lograda | Cambios en commits separados, cada uno con el pipeline en verde |
| Jenkins no alcanza el API server desde el contenedor | Alta | Stage Deploy en rojo | `host.docker.internal` + `tls-server-name`; el `sed` de la guía como respaldo |
| Docker Desktop no permite clúster multinodo | Media | No hay demostración de reparto entre zonas | Probar el modo kind; si no hay, multizona solo en el análisis prospectivo |
| Poco tiempo antes de la entrega | Alta | Entrega incompleta | Priorizar lo obligatorio del enunciado y luego subir nivel por criterio |

## 4. Deuda técnica que se deja anotada

- No hay `/metrics` en la API (se agrega en la Fase 3).
- No hay escaneo de dependencias, de secretos ni de imagen.
- No hay escaneo de los manifiestos ni de Terraform.
- El estado de Terraform será local (se justifica en un ADR).
