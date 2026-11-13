"""Esquemas Pydantic que validan las peticiones y dan forma a las respuestas."""
from pydantic import BaseModel, ConfigDict, Field, field_validator

# Los límites coinciden con el tamaño de las columnas de TaskDB.
TITLE_MAX = 200
DESCRIPTION_MAX = 500


class TaskCreate(BaseModel):
    """Body de POST /tasks/."""

    model_config = ConfigDict(str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=TITLE_MAX)
    description: str | None = Field(default=None, max_length=DESCRIPTION_MAX)


class TaskUpdate(BaseModel):
    """Body de PUT /tasks/{id}. Los campos que no llegan se dejan como están."""

    model_config = ConfigDict(str_strip_whitespace=True)

    title: str | None = Field(default=None, min_length=1, max_length=TITLE_MAX)
    description: str | None = Field(default=None, max_length=DESCRIPTION_MAX)
    completed: bool | None = None

    @field_validator("title", "completed")
    @classmethod
    def reject_null(cls, value: str | bool | None) -> str | bool:
        """Rechaza un null explícito: en la tabla estas columnas son obligatorias."""
        if value is None:
            raise ValueError("no puede ser null")
        return value


class TaskResponse(BaseModel):
    """Tarea tal como la devuelve la API."""

    model_config = ConfigDict(from_attributes=True)  # permite leer desde objetos TaskDB

    id: int
    title: str
    description: str | None = None
    completed: bool
