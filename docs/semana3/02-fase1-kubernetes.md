# Fase 1 · Kubernetes base y alta disponibilidad

## Qué se creó

| Archivo | Qué hace | Qué se agregó sobre la guía |
|---|---|---|
| `k8s/namespace.yaml` | Namespace `devops-project` | Pod Security Admission en modo `restricted` |
| `k8s/configmap.yaml` | `PYTHONUNBUFFERED` y `APP_ENV` | Label `app: taskapi` |
| `k8s/deployment.yaml` | 2 réplicas, probes, emptyDir | RollingUpdate 1/0, startupProbe, `preStop`, securityContext restringido, raíz de solo lectura, `topologySpreadConstraints`, sin token de ServiceAccount |
| `k8s/service.yaml` | LoadBalancer 80 → 8000 | Puerto con nombre |
| `k8s/hpa.yaml` | 2 a 5 pods al 60 % de CPU | `behavior` para subir rápido y bajar despacio |
| `k8s/pdb.yaml` | PodDisruptionBudget | Nuevo: siempre queda 1 pod |

Cambios fuera de `k8s/`:
- `Dockerfile`: `appuser` con UID 1000 fijo y `USER 1000`. Sin un UID numérico, `runAsNonRoot` impide que el pod arranque.
- `pytest` y `httpx` pasan de `requirements.txt` a `requirements-dev.txt`. La imagen queda sin herramientas de test. El stage Test de Jenkins ya instalaba `requirements-dev.txt`; el workflow de GitHub Actions se cambió para que haga lo mismo.

ResourceQuota, LimitRange, NetworkPolicy y el RBAC del deployer quedan para la Fase 2, porque los va a manejar Terraform.

## Por qué cada decisión (borrador para los ADR)

- **`maxUnavailable: 0` y `maxSurge: 1`.** Con 2 réplicas, el valor por defecto (25 %) redondea a 0 pods no disponibles y 1 extra, que da el mismo resultado. Se escribe explícito para que la intención quede en el manifiesto y no dependa de un redondeo.
- **`preStop: sleep 5`.** Cuando un pod empieza a terminar, el kubelet manda SIGTERM al mismo tiempo que el pod sale de los endpoints del Service. Durante ese intervalo pueden llegar peticiones a un uvicorn que ya se está cerrando. Esperar 5 s cubre esa ventana y es lo que permite que el bucle de prueba dé 0 errores.
- **startupProbe.** Reemplaza los `initialDelaySeconds` fijos de la guía. La liveness no reinicia un pod que está arrancando lento, y uno que arranca rápido queda listo antes.
- **`readOnlyRootFilesystem`.** Si alguien logra ejecutar código en el contenedor, no puede modificar la aplicación. Solo `/app/data` (SQLite) y `/tmp` son escribibles.
- **`topologySpreadConstraints` con `ScheduleAnyway`.** En un nodo no hace nada. En un clúster con varios nodos o zonas reparte las réplicas, sin dejar pods en Pending si no se puede.

## Comandos (PowerShell, desde la raíz del repo)

```powershell
# 0. Reconstruir y publicar la imagen con USER 1000 (o correr el pipeline de la Semana 2)
docker build -t vitokor123/devops-taskapi:latest .
docker run --rm vitokor123/devops-taskapi:latest id
#   Esperado: uid=1000(appuser) gid=1000(appuser)
docker push vitokor123/devops-taskapi:latest

# 1. metrics-server (Docker Desktop no lo trae)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
kubectl top nodes

# 2. Validar contra el API server sin crear nada
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/ --dry-run=server

# 3. Aplicar
kubectl apply -f k8s/
kubectl rollout status deployment/taskapi -n devops-project --timeout=120s

# 4. DoD
kubectl get all,pdb,hpa -n devops-project
curl.exe http://localhost/health
```

El patch está escrito para PowerShell 7.3 o superior, que pasa las comillas tal cual a los programas externos. En Windows PowerShell 5.1 hay que escapar cada comilla doble como `\"`. Si falla en cualquier versión, el camino sin problemas de comillas es un archivo:

```powershell
'[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' | Set-Content patch-ms.json
kubectl patch deployment metrics-server -n kube-system --type=json --patch-file=patch-ms.json
Remove-Item patch-ms.json
```

## Prueba de alta disponibilidad (borrar un pod sin cortar el servicio)

En una terminal deja corriendo el bucle; en otra borra un pod.

```powershell
# Terminal 1: una petición cada 200 ms, cuenta los errores
$ok=0; $fail=0
while ($true) {
  try { Invoke-WebRequest http://localhost/health -TimeoutSec 2 -UseBasicParsing | Out-Null; $ok++ }
  catch { $fail++ }
  Write-Host -NoNewline "`rOK: $ok  FALLAS: $fail   "
  Start-Sleep -Milliseconds 200
}

# Terminal 2
kubectl get pods -n devops-project
kubectl delete pod <nombre-de-un-pod> -n devops-project
kubectl get pods -n devops-project -w
```

Esperado: FALLAS en 0 o muy cerca. El Service deja de mandar tráfico al pod borrado y el Deployment crea uno nuevo. Ctrl+C para cortar el bucle y captura la pantalla.

## Evidencias de esta fase

1. `docker run --rm ... id` con uid=1000
2. `kubectl top nodes` funcionando
3. `kubectl get all,pdb,hpa -n devops-project` con 2/2 pods y el HPA mostrando un porcentaje (no `<unknown>`)
4. `curl.exe http://localhost/health` → `{"status":"ok"}`
5. Captura del bucle con 0 fallas tras borrar un pod
