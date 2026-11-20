#!/bin/bash
# Arranca como root solo para dar permisos al socket de Docker que llega
# montado desde el host, y luego baja al usuario jenkins con gosu.
set -e

# Dar acceso al socket de Docker al usuario jenkins
chmod 666 /var/run/docker.sock 2>/dev/null || true

# Ejecutar Jenkins como usuario jenkins (no como root).
# tini queda como PID 1 para recoger procesos zombi de los builds.
exec gosu jenkins /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
