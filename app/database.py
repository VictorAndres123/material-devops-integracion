"""Motor de base de datos, fábrica de sesiones, modelo ORM y dependencia get_db."""
import os
from collections.abc import Generator

from sqlalchemy import Boolean, Column, Integer, String, create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./tasks.db")

# SQLite solo deja usar la conexión desde el hilo que la creó.
# FastAPI atiende las peticiones en varios hilos, así que se desactiva esa comprobación.
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class TaskDB(Base):
    """Fila de la tabla tasks."""

    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    description = Column(String(500), nullable=True)
    completed = Column(Boolean, default=False, nullable=False)


def get_db() -> Generator[Session, None, None]:
    """Abre una sesión por petición y la cierra al terminar, haya error o no."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
