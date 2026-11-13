"""Carga 10 tareas de ejemplo en la base de datos.

Uso:
    py seed.py            inserta las tareas si la tabla está vacía
    py seed.py --force    borra la tabla y la vuelve a cargar
"""
import sys

from app.database import Base, SessionLocal, TaskDB, engine

TASKS: list[dict[str, str | bool]] = [
    # Semana 1: completadas
    {
        "title": "Crear estructura FastAPI",
        "description": "Scaffolding del proyecto, requirements.txt y app/",
        "completed": True,
    },
    {
        "title": "Implementar CRUD de tareas",
        "description": "GET, POST, PUT, DELETE con SQLAlchemy",
        "completed": True,
    },
    {
        "title": "Tests con pytest",
        "description": "11 tests con BD aislada usando dependency override",
        "completed": True,
    },
    {
        "title": "Dockerfile multistage",
        "description": "Imagen slim con usuario sin privilegios",
        "completed": True,
    },
    # Semana 2: pendientes
    {
        "title": "Configurar Jenkins",
        "description": "Jenkins LTS con docker-compose en jenkins/",
        "completed": False,
    },
    {
        "title": "Escribir el Jenkinsfile",
        "description": "Stages Checkout, Test, Build y Push",
        "completed": False,
    },
    {
        "title": "Conectar Jenkins con GitHub",
        "description": "Cada commit dispara el pipeline",
        "completed": False,
    },
    # Semana 3: pendientes
    {
        "title": "Desplegar en Kubernetes",
        "description": "Deployment y Service para la API",
        "completed": False,
    },
    {
        "title": "Configurar probes de salud",
        "description": "Liveness y readiness sobre /health",
        "completed": False,
    },
    {
        "title": "Ejecutar el pod sin root",
        "description": "securityContext con runAsNonRoot",
        "completed": False,
    },
]


def seed(force: bool = False) -> None:
    """Inserta las tareas de ejemplo.

    Si la tabla ya tiene datos no hace nada, salvo que force sea True:
    en ese caso la borra y la carga de nuevo con los IDs del 1 al 10.
    """
    if force:
        Base.metadata.drop_all(bind=engine)
        print("Base de datos reiniciada.")
    Base.metadata.create_all(bind=engine)

    with SessionLocal() as db:
        if db.query(TaskDB).count() > 0:
            print("La BD ya tiene datos. Usa --force para reiniciar.")
            return
        db.add_all(TaskDB(**task) for task in TASKS)
        db.commit()

    print(f"Seed completado: {len(TASKS)} tareas insertadas en {engine.url.database}")
    print("Prueba la API en: http://localhost:8000/docs")


if __name__ == "__main__":
    seed(force="--force" in sys.argv)
