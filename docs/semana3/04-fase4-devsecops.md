# Fase 4 · Stage Deploy y DevSecOps dentro de los cinco stages

## Resultado

| Build | Commit | Resultado | Qué demuestra |
|---|---|---|---|
| #9 | `e1d59b1` | FAILURE en Test | pip-audit encontró **14 vulnerabilidades en Starlette 0.38.6** (dependencia de FastAPI 0.115.0) y detuvo el pipeline antes de construir la imagen. Build, Push y Deploy no corrieron. |
| #10 | `65b98c9` | FAILURE en Test | FastAPI 0.165.0 (Starlette 1.10.0) corrige las 14. El build cayó por un error del propio Jenkinsfile: pip-audit no crea el archivo de `--output` cuando no hay hallazgos y el `cat` siguiente falló. |
| #11 | `35f82eb` | **SUCCESS** | Los cinco stages en verde, con todos los controles de seguridad pasando. |

En el Stage View, los stages que no corrieron después de un fallo salen en rojo con la palabra "failed". En la consola dicen `Stage "Build" skipped due to earlier failure(s)`. No fallaron: se saltaron.

## Qué corrió en el build #11

| Stage | Control | Resultado |
|---|---|---|
| Test | pytest | 11/11, cobertura 92,47 % (mínimo exigido 85 %) |
| Test | gitleaks v8.18.4 (historial completo) | 16 commits, sin secretos |
| Test | bandit 1.9.4 (severidad y confianza media o más) | 0 hallazgos en 126 líneas |
| Test | pip-audit 2.10.1 sobre `requirements.txt` | Sin vulnerabilidades conocidas |
| Test | Trivy config sobre `k8s/` | 0 HIGH/CRITICAL en 6 manifiestos |
| Test | Trivy config sobre `infra/terraform/` | 0 HIGH/CRITICAL |
| Build | Trivy image (CRITICAL con parche disponible) | 0 en Debian 13.7 y en los 18 paquetes Python |
| Build | SBOM CycloneDX | `reports/sbom.cdx.json` archivado |
| Push | `:11` y `:latest` | Mismo digest `sha256:f0ab28dd…2323` |
| Deploy | kubectl con `jenkins-deployer` | Cliente y servidor v1.32.2, TLS verificado |
| Deploy | Rollout | Un solo rollout, unos 22 s. `set image` no generó un segundo (H13 resuelto) |
| Deploy | Smoke test `http://host.docker.internal/health` | `{"status":"ok"}` |
| Deploy | Estado final | 2 pods nuevos Running, HPA en 3 %/60 % |

## Decisiones

**Seguridad dentro de los cinco stages y no en stages nuevos.** El enunciado pide ver exactamente Checkout, Test, Build, Push y Deploy. Meter los controles como pasos de cada stage cumple eso y además los ubica donde corresponde en el ciclo: lo que se revisa sobre el código, antes de construir; lo que se revisa sobre la imagen, antes de publicarla.

**Umbrales.** bandit falla con severidad media o más. pip-audit falla con cualquier vulnerabilidad conocida. Trivy config falla con HIGH o CRITICAL. Trivy image falla solo con CRITICAL que tenga parche (`--ignore-unfixed`). Si se bloqueara también por HIGH sin parche, el pipeline quedaría detenido por fallas de la imagen base que el equipo no puede corregir. Los HIGH quedan en el reporte para revisarlos.

**Herramientas en contenedores fijados.** gitleaks y Trivy corren con `docker run` y no se instalan en la imagen de Jenkins. Trivy va fijado por digest. Así no hay que reconstruir Jenkins para actualizarlas, y un build de hoy da el mismo resultado que uno de dentro de un mes. Como el daemon de Docker está en el host y no ve el workspace por ruta, los contenedores usan `--volumes-from jenkins`.

**Kubeconfig de permisos mínimos y TLS verificado.** La guía monta el kubeconfig de administrador y desactiva la verificación del certificado con dos `sed`. En esta versión de Docker Desktop el API server está en `kubernetes.docker.internal:6443`, ese nombre resuelve desde el contenedor (192.168.65.3) y está en los SAN del certificado. Así que no hace falta ningún parche. El kubeconfig lo genera Terraform para el ServiceAccount `jenkins-deployer` y vive en Jenkins como credencial *Secret file*.

**Un solo rollout por build.** Antes del `kubectl apply`, la copia del workspace de `deployment.yaml` se reescribe con la imagen `:N`. El `kubectl set image` que exige el enunciado queda como confirmación y no genera un segundo rollout.

**Rollback automático.** Si el rollout pasa de 120 s o el smoke test falla, el `post { failure }` del stage hace `kubectl rollout undo`. La anotación `kubernetes.io/change-cause` deja en `kubectl rollout history` qué build y qué commit generó cada revisión.

## Riesgos que quedan

- `docker login` guarda el token sin cifrar en `/var/jenkins_home/.docker/config.json` mientras dura el build. El `docker logout` del `post` lo borra al final. La solución completa es un *credential helper* o construir con Kaniko o BuildKit sin daemon.
- El socket de Docker sigue abierto dentro del contenedor de Jenkins (H4).
- La imagen final conserva pip 25.0.1, que viene en la imagen base. No tiene vulnerabilidades reportadas hoy, pero no se usa en runtime y se podría quitar.

## Evidencias

1. Stage View del #9 detenido en Test
2. Consola del #9 con la tabla de pip-audit (14 vulnerabilidades) y `exit 1`
3. Stage View del #11 con los cinco stages en verde
4. Consola del #11: gitleaks, bandit, pip-audit, Trivy config (2) y Trivy image
5. Artefactos del #11 (`reports/`), con el SBOM
6. Pestaña Tags de Docker Hub: `11` y `latest` con el mismo digest
7. "Test Result" del #11: 11/11
8. `kubectl rollout history deployment/taskapi -n devops-project` mostrando el change-cause del build #11
