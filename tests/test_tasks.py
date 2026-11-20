"""Pruebas de integración de la API de tareas.

Cada test corre contra una BD SQLite en memoria. La dependencia get_db de la
app se sustituye con dependency_overrides, así que tasks.db nunca se toca.
"""
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app

TEST_DATABASE_URL = "sqlite:///:memory:"

# StaticPool reutiliza una sola conexión. Sin él, cada conexión nueva abriría
# una BD en memoria distinta y las tablas creadas en el fixture no se verían.
engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db() -> Generator[Session, None, None]:
    """Versión de get_db que entrega sesiones de la BD en memoria."""
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db

client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_db() -> Generator[None, None, None]:
    """Crea las tablas antes de cada test y las borra al terminar."""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


def crear_tarea(title: str, description: str | None = None) -> dict[str, object]:
    """Crea una tarea por la API y devuelve el JSON de la respuesta."""
    r = client.post("/tasks/", json={"title": title, "description": description})
    assert r.status_code == 201
    return r.json()


# --- Health ---------------------------------------------------------------


def test_health_check() -> None:
    """GET /health responde 200 con el estado ok."""
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "roto-a-proposito"}  # fallo intencional para la evidencia


# --- Crear ----------------------------------------------------------------


def test_create_task() -> None:
    """POST con título y descripción crea la tarea sin completar."""
    r = client.post("/tasks/", json={"title": "Mi tarea", "description": "Desc"})
    assert r.status_code == 201
    assert r.json() == {
        "id": 1,
        "title": "Mi tarea",
        "description": "Desc",
        "completed": False,
    }


def test_create_task_sin_descripcion() -> None:
    """La descripción es opcional y queda en null."""
    r = client.post("/tasks/", json={"title": "Solo título"})
    assert r.status_code == 201
    assert r.json()["title"] == "Solo título"
    assert r.json()["description"] is None
    assert r.json()["completed"] is False


# --- Listar ---------------------------------------------------------------


def test_listar_tareas_vacia() -> None:
    """Sin tareas, el listado es una lista vacía."""
    r = client.get("/tasks/")
    assert r.status_code == 200
    assert r.json() == []


def test_listar_tareas() -> None:
    """El listado devuelve todas las tareas en orden de creación."""
    crear_tarea("Primera")
    crear_tarea("Segunda")

    r = client.get("/tasks/")
    assert r.status_code == 200
    assert [t["title"] for t in r.json()] == ["Primera", "Segunda"]


# --- Obtener por ID -------------------------------------------------------


def test_get_task_existente() -> None:
    """GET por ID devuelve la misma tarea que se creó."""
    tarea = crear_tarea("Buscar por ID", description="Detalle")

    r = client.get(f"/tasks/{tarea['id']}")
    assert r.status_code == 200
    assert r.json() == tarea


def test_get_task_no_existente() -> None:
    """GET de un ID que no existe responde 404."""
    r = client.get("/tasks/999")
    assert r.status_code == 404
    assert r.json() == {"detail": "Tarea no encontrada"}


# --- Editar ---------------------------------------------------------------


def test_update_task() -> None:
    """PUT cambia solo los campos enviados y el cambio se guarda."""
    tarea = crear_tarea("Título original", description="Sin cambios")

    r = client.put(f"/tasks/{tarea['id']}", json={"completed": True})
    assert r.status_code == 200
    assert r.json()["completed"] is True
    # El PUT es parcial: lo que no se envía conserva su valor.
    assert r.json()["title"] == "Título original"
    assert r.json()["description"] == "Sin cambios"

    # El cambio quedó guardado, no solo devuelto en la respuesta.
    assert client.get(f"/tasks/{tarea['id']}").json()["completed"] is True


def test_update_task_no_existente() -> None:
    """PUT sobre un ID que no existe responde 404."""
    r = client.put("/tasks/999", json={"title": "No existe"})
    assert r.status_code == 404
    assert r.json() == {"detail": "Tarea no encontrada"}


# --- Eliminar -------------------------------------------------------------


def test_eliminar_tarea() -> None:
    """DELETE responde 204 y la tarea deja de existir."""
    tarea = crear_tarea("Para borrar")

    r = client.delete(f"/tasks/{tarea['id']}")
    assert r.status_code == 204
    assert r.content == b""

    assert client.get(f"/tasks/{tarea['id']}").status_code == 404


def test_eliminar_tarea_no_existente() -> None:
    """DELETE de un ID que no existe responde 404."""
    r = client.delete("/tasks/999")
    assert r.status_code == 404
    assert r.json() == {"detail": "Tarea no encontrada"}
