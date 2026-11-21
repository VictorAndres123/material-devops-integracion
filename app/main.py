"""Punto de entrada de la aplicación FastAPI."""
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

from app.database import Base, engine
from app.routers import tasks


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Crea las tablas cuando arranca el servidor.

    Se hace aquí y no al importar el módulo para que los tests, que importan
    `app` pero usan su propia BD en memoria, no generen el archivo tasks.db.
    """
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="DevOps Task Manager API",
    description="API REST de gestión de tareas. Proyecto Integrador DevOps",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(tasks.router)

# Métricas para Prometheus en GET /metrics: peticiones por ruta, método y
# código (http_requests_total) y latencia (http_request_duration_seconds).
# /metrics no se mide a sí mismo. No aparece en Swagger.
Instrumentator(excluded_handlers=["/metrics"]).instrument(app).expose(
    app, include_in_schema=False
)


@app.get("/health", tags=["Health"])
def health_check() -> dict[str, str]:
    """Endpoint de salud para las liveness y readiness probes de Kubernetes."""
    return {"status": "ok"}
