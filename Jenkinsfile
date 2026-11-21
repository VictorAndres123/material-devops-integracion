// Pipeline CI/CD del DevOps Task Manager API (Semana 3).
// Cada cambio en main pasa por Checkout → Test → Build → Push → Deploy y
// termina desplegado en Kubernetes sin cortar el servicio.
//
// Los controles de seguridad (shift left) van DENTRO de los cinco stages
// para que la vista de Jenkins siga mostrando exactamente los cinco que
// pide el enunciado:
//   Test   → pytest + cobertura, gitleaks (secretos), bandit (SAST),
//            pip-audit (dependencias), Trivy sobre k8s/ e infra/terraform
//   Build  → docker build, Trivy sobre la imagen, SBOM CycloneDX
//   Deploy → kubectl con un ServiceAccount de permisos mínimos, smoke test
//            y rollback automático si algo falla
// Los reportes quedan como artefactos del build (carpeta reports/).
pipeline {
    agent any

    options {
        // Solo se guardan los últimos 10 builds: logs y reportes viejos
        // llenan el volumen jenkins_home.
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Si algo se cuelga (un pull lento, un rollout que no termina), el
        // build se corta en vez de bloquear el único executor.
        timeout(time: 30, unit: 'MINUTES')
        // Dos builds a la vez pelearían por el tag :latest, por el mismo
        // daemon de Docker y por el mismo Deployment.
        disableConcurrentBuilds()
        // Hora en cada línea de la consola; sirve para medir cada paso.
        timestamps()
    }

    environment {
        IMAGE_NAME    = "vitokor123/devops-taskapi"
        K8S_NAMESPACE = "devops-project"
        // Herramientas de seguridad fijadas: el mismo build da el mismo
        // resultado hoy y dentro de un mes. Trivy va fijado por digest.
        TRIVY_IMAGE    = "aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"
        GITLEAKS_IMAGE = "zricethezav/gitleaks:v8.18.4"
    }

    triggers {
        // H reparte la hora de consulta para que varios jobs no le
        // pregunten a GitHub en el mismo minuto.
        pollSCM('H/5 * * * *')
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm    // clona la rama configurada en el job (*/main)
            }
        }

        stage('Test') {
            steps {
                // 1) Pruebas. requirements-dev.txt incluye requirements.txt,
                //    pytest-cov, bandit y pip-audit. --cov-fail-under hace que
                //    el build falle si la cobertura baja del 85 %.
                sh '''
                    mkdir -p reports
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet --disable-pip-version-check -r requirements-dev.txt
                    pytest tests/ -v --junit-xml=test-report.xml \
                        --cov=app --cov-report=xml:coverage.xml --cov-report=term \
                        --cov-fail-under=85
                '''

                // 2) Secretos en todo el historial de git. Corre en un
                //    contenedor que comparte los volúmenes de Jenkins
                //    (--volumes-from) porque el daemon de Docker está en el
                //    host y no ve el workspace por ruta. -u evita que el
                //    reporte quede con dueño root y cleanWs no pueda borrarlo.
                sh '''
                    echo "== gitleaks: secretos en el historial"
                    docker run --rm --volumes-from jenkins -u "$(id -u):$(id -g)" -w "$WORKSPACE" \
                        "$GITLEAKS_IMAGE" detect --source . --redact --no-banner \
                        --report-format json --report-path reports/gitleaks.json
                '''

                // 3) SAST: falla con hallazgos de severidad media o más.
                // 4) Dependencias de runtime con vulnerabilidades conocidas.
                sh '''
                    . .venv/bin/activate
                    echo "== bandit: análisis estático del código"
                    bandit -r app --severity-level medium --confidence-level medium \
                        -f txt -o reports/bandit.txt || { cat reports/bandit.txt; exit 1; }
                    cat reports/bandit.txt

                    # pip-audit solo crea el archivo de --output cuando hay
                    # hallazgos; por eso la salida se redirige desde la shell
                    # y el reporte existe siempre, con o sin vulnerabilidades.
                    echo "== pip-audit: dependencias de requirements.txt"
                    rc=0
                    pip-audit -r requirements.txt --progress-spinner off \
                        > reports/pip-audit.txt 2>&1 || rc=$?
                    cat reports/pip-audit.txt
                    [ "$rc" -eq 0 ] || exit "$rc"
                '''

                // 5) Configuración insegura en manifiestos y Terraform.
                //    La salida se redirige desde esta shell para que los
                //    reportes los escriba el usuario jenkins.
                sh '''
                    for target in k8s infra/terraform; do
                        name=$(echo "$target" | tr '/' '-')
                        echo "== Trivy config: $target"
                        rc=0
                        docker run --rm --volumes-from jenkins -w "$WORKSPACE" \
                            -v trivy-cache:/root/.cache/trivy \
                            "$TRIVY_IMAGE" config --quiet --exit-code 1 \
                            --severity HIGH,CRITICAL "$target" > "reports/trivy-config-$name.txt" 2>&1 || rc=$?
                        cat "reports/trivy-config-$name.txt"
                        [ "$rc" -eq 0 ] || exit "$rc"
                    done
                '''
            }
            post {
                always {
                    // Se publican aunque el stage falle: es justo cuando más
                    // importa ver qué test se rompió.
                    junit allowEmptyResults: true, testResults: 'test-report.xml'
                    recordCoverage(
                        tools: [[parser: 'COBERTURA', pattern: 'coverage.xml']],
                        id: 'coverage',
                        name: 'Cobertura (pytest-cov)',
                        sourceCodeRetention: 'LAST_BUILD'
                    )
                }
            }
        }

        stage('Build') {
            steps {
                // Las etiquetas OCI dejan dentro de la imagen el commit y el
                // build que la generaron (docker inspect las muestra).
                sh '''
                    docker build \
                        --label org.opencontainers.image.title=devops-taskapi \
                        --label org.opencontainers.image.revision="$GIT_COMMIT" \
                        --label jenkins.build="$BUILD_NUMBER" \
                        -t "$IMAGE_NAME:$BUILD_NUMBER" .
                    docker tag "$IMAGE_NAME:$BUILD_NUMBER" "$IMAGE_NAME:latest"
                '''

                // Escaneo de la imagen ANTES de publicarla: si tiene una
                // vulnerabilidad CRITICAL con parche disponible, no sale a
                // Docker Hub. El SBOM lista todo lo que lleva la imagen.
                sh '''
                    echo "== Trivy image: $IMAGE_NAME:$BUILD_NUMBER"
                    rc=0
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        "$TRIVY_IMAGE" image --quiet --exit-code 1 --ignore-unfixed \
                        --severity CRITICAL "$IMAGE_NAME:$BUILD_NUMBER" > reports/trivy-image.txt 2>&1 || rc=$?
                    cat reports/trivy-image.txt

                    echo "== SBOM CycloneDX"
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        "$TRIVY_IMAGE" image --quiet --format cyclonedx \
                        "$IMAGE_NAME:$BUILD_NUMBER" > reports/sbom.cdx.json

                    [ "$rc" -eq 0 ] || exit "$rc"
                '''
            }
        }

        stage('Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    // Comillas simples: las variables las expande la shell y
                    // no Groovy, así el token nunca queda escrito en el
                    // script que Jenkins guarda. --password-stdin evita que
                    // aparezca en la lista de procesos (ps aux).
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push "$IMAGE_NAME:$BUILD_NUMBER"
                        docker push "$IMAGE_NAME:latest"
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                // Kubeconfig del ServiceAccount jenkins-deployer (lo genera
                // Terraform). Solo puede tocar el namespace devops-project y
                // verifica el certificado del API server: no hace falta el
                // sed ni insecure-skip-tls-verify de la guía, porque desde el
                // contenedor kubernetes.docker.internal ya resuelve y está
                // en los SAN del certificado.
                withCredentials([file(credentialsId: 'k8s-deployer-kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl version
                        kubectl auth can-i patch deployments -n "$K8S_NAMESPACE"

                        # La copia del workspace ya apunta a la imagen de este
                        # build. Así "kubectl apply" hace un solo rollout, en
                        # vez de volver a :latest y que "set image" dispare
                        # un segundo (hallazgo H13 de la auditoría).
                        sed -i "s|image: $IMAGE_NAME:latest|image: $IMAGE_NAME:$BUILD_NUMBER|" k8s/deployment.yaml

                        # El namespace primero: kubectl recorre k8s/ en orden
                        # alfabético y configmap.yaml va antes.
                        kubectl apply -f k8s/namespace.yaml
                        kubectl apply -f k8s/

                        # Confirma la imagen exacta del build (si el apply ya
                        # la dejó así, no genera otro rollout).
                        kubectl set image deployment/taskapi taskapi="$IMAGE_NAME:$BUILD_NUMBER" -n "$K8S_NAMESPACE"
                        kubectl annotate deployment/taskapi -n "$K8S_NAMESPACE" --overwrite \
                            kubernetes.io/change-cause="Jenkins build #$BUILD_NUMBER, commit ${GIT_COMMIT:-desconocido}"

                        kubectl rollout status deployment/taskapi -n "$K8S_NAMESPACE" --timeout=120s
                    '''
                }

                // Smoke test por el mismo camino que un usuario: el Service
                // LoadBalancer publicado en el host.
                sh '''
                    curl -fsS --retry 10 --retry-delay 3 --retry-connrefused \
                        http://host.docker.internal/health
                    echo
                '''
            }
            post {
                failure {
                    // Si el rollout o el smoke test fallan, vuelve a la
                    // versión anterior. La imagen rota queda en Docker Hub
                    // para investigar, pero no atiende tráfico.
                    withCredentials([file(credentialsId: 'k8s-deployer-kubeconfig', variable: 'KUBECONFIG')]) {
                        sh '''
                            echo "Deploy falló: rollback a la revisión anterior"
                            kubectl rollout undo deployment/taskapi -n "$K8S_NAMESPACE" || true
                            kubectl rollout status deployment/taskapi -n "$K8S_NAMESPACE" --timeout=120s || true
                            kubectl rollout history deployment/taskapi -n "$K8S_NAMESPACE" || true
                        '''
                    }
                }
                success {
                    withCredentials([file(credentialsId: 'k8s-deployer-kubeconfig', variable: 'KUBECONFIG')]) {
                        sh 'kubectl get pods,svc,hpa -n "$K8S_NAMESPACE" -o wide'
                    }
                }
            }
        }
    }

    post {
        always {
            // Reportes de seguridad y SBOM como artefactos del build.
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true, fingerprint: true

            // docker logout borra la sesión guardada en el contenedor Jenkins.
            // Luego se quita la etiqueta del build: la imagen sigue viva con
            // :latest y sirve de caché para el siguiente build; las de builds
            // anteriores quedan huérfanas y el prune las borra, así el disco
            // de Docker Desktop no crece con cada ejecución.
            sh '''
                docker logout || true
                docker rmi ${IMAGE_NAME}:${BUILD_NUMBER} 2>/dev/null || true
                docker image prune -f --filter "label=org.opencontainers.image.title=devops-taskapi" || true
            '''
            cleanWs()   // borra el workspace: venv, reportes y código clonado
        }
        success {
            echo "Pipeline OK — imagen ${IMAGE_NAME}:${BUILD_NUMBER} publicada y desplegada en Kubernetes"
        }
        failure {
            echo "Pipeline FAILED en build #${BUILD_NUMBER} — revisar logs y reports/"
        }
    }
}
