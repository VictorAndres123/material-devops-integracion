// Pipeline CI del DevOps Task Manager API (Semana 2).
// Cada cambio en main pasa por Checkout → Test → Build → Push y termina
// con la imagen publicada en Docker Hub, sin pasos manuales.
pipeline {
    agent any

    options {
        // Solo se guardan los últimos 10 builds: logs y reportes viejos
        // llenan el volumen jenkins_home.
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Si algo se cuelga (un pull lento, un test que no termina), el
        // build se corta en vez de bloquear el único executor.
        timeout(time: 20, unit: 'MINUTES')
        // Dos builds a la vez pelearían por el tag :latest y por el
        // mismo daemon de Docker.
        disableConcurrentBuilds()
        // Hora en cada línea de la consola; sirve para medir cada paso.
        timestamps()
    }

    environment {
        IMAGE_NAME = "vitokor123/devops-taskapi"
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
                // requirements-dev.txt incluye requirements.txt + pytest-cov.
                // --cov-fail-under hace que el build falle si la cobertura
                // baja del 85 % (hoy está en 92 %), aunque los tests pasen.
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet --disable-pip-version-check -r requirements-dev.txt
                    pytest tests/ -v --junit-xml=test-report.xml \
                        --cov=app --cov-report=xml:coverage.xml --cov-report=term \
                        --cov-fail-under=85
                '''
            }
            post {
                always {
                    // Se publican aunque el stage falle: es justo cuando más
                    // importa ver qué test se rompió.
                    junit 'test-report.xml'
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
                // Comillas simples: la shell expande las variables, y si
                // GIT_COMMIT no existiera quedaría vacía en vez de romper Groovy.
                sh '''
                    docker build \
                        --label org.opencontainers.image.title=devops-taskapi \
                        --label org.opencontainers.image.revision="$GIT_COMMIT" \
                        --label jenkins.build="$BUILD_NUMBER" \
                        -t "$IMAGE_NAME:$BUILD_NUMBER" .
                '''
                sh "docker tag  ${IMAGE_NAME}:${BUILD_NUMBER} ${IMAGE_NAME}:latest"
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
                        docker push ${IMAGE_NAME}:${BUILD_NUMBER}
                        docker push ${IMAGE_NAME}:latest
                    '''
                }
            }
        }
    }

    post {
        always {
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
            echo "Pipeline OK — imagen ${IMAGE_NAME}:${BUILD_NUMBER} publicada en Docker Hub"
        }
        failure {
            echo "Pipeline FAILED en build #${BUILD_NUMBER} — revisar logs"
        }
    }
}
