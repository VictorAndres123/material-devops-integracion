# ── Etapa 1: builder ─────────────────────────────────────────
# Instala las dependencias en /install para copiarlas luego a la imagen final.
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Etapa 2: runtime ─────────────────────────────────────────
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Solo las dependencias ya instaladas; pip y su caché se quedan en el builder
COPY --from=builder /install /usr/local

# Usuario sin privilegios y carpeta propia para el archivo SQLite.
# Se usa useradd porque la base Debian 13 (trixie) de python:3.12-slim ya no trae adduser.
RUN useradd --uid 1000 --create-home appuser \
    && mkdir -p /app/data \
    && chown appuser:appuser /app/data

COPY app/ ./app/
COPY seed.py .

# UID numérico: Kubernetes solo puede comprobar runAsNonRoot con un número.
USER 1000

# Ruta de la BD dentro del contenedor (se puede cambiar con -e DATABASE_URL=...)
ENV DATABASE_URL=sqlite:////app/data/tasks.db

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
