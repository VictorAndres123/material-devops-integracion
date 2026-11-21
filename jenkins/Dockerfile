# Imagen de Jenkins para el pipeline CI/CD (Semanas 2 y 3).
# La oficial no trae el cliente de Docker ni Python 3, y el pipeline
# necesita los dos: Python para correr pytest y Docker para build/push.
FROM jenkins/jenkins:lts-jdk17

USER root

# ── Docker CLI ──────────────────────────────────────────────
# Solo el cliente (docker-ce-cli). El daemon es el de Docker Desktop,
# al que se llega por el socket montado en docker-compose.yml.
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
         https://download.docker.com/linux/debian \
         $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# ── Python 3 + venv (para ejecutar pytest en el pipeline) ───
# python3-venv es necesario porque Debian no deja instalar paquetes con
# pip en el Python del sistema (PEP 668); el stage Test usa un venv.
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

# ── kubectl (Semana 3: stage Deploy) ────────────────────────
# Versión fija igual a la del clúster de Docker Desktop (v1.32.2) y
# checksum verificado: si el binario descargado no coincide con el
# publicado por Kubernetes, el build de la imagen falla.
ARG KUBECTL_VERSION=v1.32.2
RUN curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    curl -fsSLo /tmp/kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check && \
    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl && \
    rm /tmp/kubectl /tmp/kubectl.sha256

# ── Acceso al socket de Docker ───────────────────────────────
RUN groupadd -f docker && usermod -aG docker jenkins

# ── gosu: cambia de root a jenkins sin perder acceso al socket
# Binario amd64: la máquina del host es x64.
RUN curl -fsSL "https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64" \
        -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu

# ── Entrypoint: chmod socket → gosu jenkins → jenkins.sh ─────
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
