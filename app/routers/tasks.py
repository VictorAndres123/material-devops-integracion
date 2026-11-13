"""Endpoints CRUD del recurso /tasks."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import TaskDB, get_db
from app.models import TaskCreate, TaskResponse, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["Tasks"])


def get_task_or_404(task_id: int, db: Session) -> TaskDB:
    """Busca la tarea por ID y responde 404 si no existe."""
    task = db.get(TaskDB, task_id)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )
    return task


@router.get("/", response_model=list[TaskResponse])
def list_tasks(db: Session = Depends(get_db)) -> list[TaskDB]:
    """Lista todas las tareas ordenadas por ID."""
    return db.query(TaskDB).order_by(TaskDB.id).all()


@router.post("/", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
def create_task(task: TaskCreate, db: Session = Depends(get_db)) -> TaskDB:
    """Crea una tarea. Siempre nace sin completar."""
    db_task = TaskDB(title=task.title, description=task.description)
    db.add(db_task)
    db.commit()
    db.refresh(db_task)
    return db_task


@router.get("/{task_id}", response_model=TaskResponse)
def get_task(task_id: int, db: Session = Depends(get_db)) -> TaskDB:
    """Devuelve una tarea por su ID."""
    return get_task_or_404(task_id, db)


@router.put("/{task_id}", response_model=TaskResponse)
def update_task(
    task_id: int, updates: TaskUpdate, db: Session = Depends(get_db)
) -> TaskDB:
    """Actualiza solo los campos que el cliente envió en el body."""
    task = get_task_or_404(task_id, db)
    for field, value in updates.model_dump(exclude_unset=True).items():
        setattr(task, field, value)
    db.commit()
    db.refresh(task)
    return task


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, db: Session = Depends(get_db)) -> None:
    """Elimina una tarea. Responde 204 sin cuerpo."""
    task = get_task_or_404(task_id, db)
    db.delete(task)
    db.commit()
