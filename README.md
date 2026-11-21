# DevOps Task Manager API

API REST para gestionar tareas, hecha con FastAPI y SQLite. Es la entrega de la Semana 1 del proyecto integrador del curso DevOps e Integración Continua (Especialización en Arquitectura de Software, CORHUILA, 2026). Sobre esta base se monta el pipeline de Jenkins en la Semana 2.

Autor: Victor Andres Rojas Meneses

## Stack

Python 3.11 o superior en local y 3.12-slim en la imagen Docker. Las versiones de las librerías están fijadas en `requirements.txt`: FastAPI 0.165.0, Uvicorn 0.30.0, SQLAlchemy 2.0.40, Pydantic 2.10.3; las de pruebas (pytest 8.2.0, httpx 0.27.0, pytest-cov) y seguridad (bandit, pip-audit) están en `requirements-dev.txt`.

## Estructura

```
material-devops-integracion/
├── app/
│   ├── __init__.py
│   ├── main.py            # instancia de FastAPI y GET /health
│   ├── database.py        # engine, SessionLocal, modelo TaskDB y get_db()
│   ├── models.py          # esquemas Pydantic: TaskCreate, TaskUpdate, TaskResponse
│   └── routers/
│       ├── __init__.py
│       └── tasks.py       # los cinco endpoints de /tasks
├── .github/workflows/
│   └── verificacion.yml   # repite la verificación en GitHub Actions
├── tests/
│   ├── __init__.py
│   └── test_tasks.py      # 11 pruebas de integración
├── Dockerfile             # imagen multietapa con usuario appuser
├── docker-compose.yml     # entorno de desarrollo con hot-reload
├── seed.py                # carga 10 tareas de ejemplo
├── requirements.txt
├── .dockerignore
└── .gitignore
```

Cada archivo de `app/` tiene una sola responsabilidad. El router no sabe cómo se abre la conexión: recibe la sesión con `Depends(get_db)`, y eso es lo que permite cambiar la base de datos en los tests sin tocar el código de la API.

## Ejecución local

Los comandos usan `py`, el lanzador de Python en Windows. En Linux o macOS se cambia por `python3`.

```
py -m pip install -r requirements.txt
py -m uvicorn app.main:app --reload
```

La API queda en http://127.0.0.1:8000 y la documentación interactiva (Swagger UI) en http://127.0.0.1:8000/docs. No hay que configurar nada más: al arrancar, la app crea `tasks.db` en la raíz del proyecto si todavía no existe.

Para guardar la base de datos en otra ruta se define la variable `DATABASE_URL` antes de arrancar, por ejemplo `sqlite:///./otra.db`.

## Endpoints

| Método | Ruta | Qué hace | Respuestas |
|--------|------|----------|------------|
| GET | `/health` | Informa que el servicio está arriba | 200 |
| GET | `/tasks/` | Lista las tareas | 200 |
| POST | `/tasks/` | Crea una tarea | 201, 422 |
| GET | `/tasks/{id}` | Devuelve una tarea | 200, 404 |
| PUT | `/tasks/{id}` | Edita los campos enviados | 200, 404, 422 |
| DELETE | `/tasks/{id}` | Elimina una tarea | 204, 404 |

`title` es obligatorio y admite entre 1 y 200 caracteres. `description` es opcional, con máximo 500. Son los mismos tamaños de las columnas de la tabla, así que un dato que pasa la validación siempre cabe en la base de datos.

El PUT es parcial. Si el body solo trae `{"completed": true}`, el título y la descripción quedan como estaban. Enviar `title` o `completed` en `null` devuelve 422, porque en la tabla esas columnas no aceptan nulos.

## Pruebas

```
py -m pytest tests/ -v
```

Son 11 pruebas de integración que llaman a la API con el `TestClient` de FastAPI (que por debajo usa httpx): una de `/health`, dos de creación, dos de listado, dos de consulta por ID, dos de edición y dos de borrado. Tres de ellas cubren el 404 cuando el ID no existe.

Las pruebas no tocan `tasks.db`. El archivo de tests crea un engine sobre `sqlite:///:memory:` con `StaticPool` y reemplaza `get_db` mediante `app.dependency_overrides`. Un fixture con `autouse=True` crea las tablas antes de cada test y las borra al terminar, de modo que ningún test depende de lo que dejó otro. Después de correr la suite no queda ningún archivo `.db` en el proyecto.

El warning que aparece al final lo emite Starlette por un alias obsoleto de anyio. No viene del código del proyecto.

## Datos de ejemplo

```
py seed.py
py seed.py --force
```

`seed.py` inserta 10 tareas que describen el avance del propio proyecto: las 4 de la Semana 1 quedan completadas y las 6 de las Semanas 2 y 3, pendientes. Si la tabla ya tiene datos, el script avisa y no inserta nada. Con `--force` borra la tabla y la carga otra vez, con los IDs del 1 al 10.

## Docker

```
docker build -t devops-task-api:local .
docker run -p 8000:8000 devops-task-api:local
```

El Dockerfile tiene dos etapas. En `builder` se instalan las dependencias en `/install`. La etapa `runtime` parte de otra `python:3.12-slim` limpia y copia solo esa carpeta, más el código de `app/` y `seed.py`. El proceso corre con el usuario `appuser`, que no es root y solo puede escribir en `/app/data`, donde queda el archivo SQLite.

Para desarrollar con hot-reload:

```
docker compose up --build
docker compose exec api python seed.py
docker compose down
```

`docker-compose.yml` usa la misma imagen, monta la carpeta `app/` del host sobre la del contenedor y arranca uvicorn con `--reload`. Al guardar un archivo de `app/`, el servidor se reinicia solo. La base de datos vive en el volumen `task-data` y se conserva entre reinicios. Con `docker compose down -v` se borra también el volumen.

## Decisiones técnicas

Las tablas se crean en el `lifespan` de FastAPI y no al importar `app.main`. Los tests importan `app` para pasarla al `TestClient`, y con un `create_all` a nivel de módulo esa importación dejaba un `tasks.db` vacío en disco cada vez que se corría pytest.

El compose monta `./app` y no la raíz del proyecto. Si se monta `.` sobre `/app`, el montaje tapa la carpeta `/app/data` que se creó en la imagen y SQLite falla al arrancar con `unable to open database file`.

El usuario se crea con `useradd` en lugar de `adduser`. La imagen `python:3.12-slim` actual se basa en Debian 13 (trixie), que ya no incluye `adduser` en la instalación mínima. `useradd` viene en el paquete `passwd` y funciona tanto en Debian 12 como en Debian 13.

`seed.py` se copia a la imagen para poder cargar los datos dentro del contenedor, que tiene su propia base de datos separada de la del host.

## Verificación

| Comando | Resultado esperado |
|---------|--------------------|
| `py -m pytest tests/ -v` | `11 passed` |
| `py seed.py` | `Seed completado: 10 tareas insertadas en ./tasks.db` |
| `py seed.py` (segunda vez) | `La BD ya tiene datos. Usa --force para reiniciar.` |
| `py seed.py --force` | `Base de datos reiniciada.` y de nuevo las 10 tareas |
| `py -m uvicorn app.main:app --reload` | `/health` responde `{"status": "ok"}` y `/docs` abre Swagger UI |
| `docker run -p 8000:8000 devops-task-api:local` | lo mismo en http://localhost:8000, y `docker exec <contenedor> whoami` responde `appuser` |
| `docker compose up --build` | el log muestra `Started reloader process` y cada cambio en `app/` reinicia el servidor |

El flujo `.github/workflows/verificacion.yml` ejecuta estos mismos pasos en GitHub Actions con cada push: los tests en Python 3.11 y 3.12, el build de la imagen, el seed dentro del contenedor y el arranque con compose. El resultado se ve en la pestaña Actions del repositorio.
