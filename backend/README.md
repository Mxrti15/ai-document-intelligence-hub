# AI Document Intelligence Hub - Backend

Backend local con FastAPI para subir documentos PDF, almacenar metadatos en SQLite,
extraer texto, ejecutar un analisis mock y consultar metricas basicas de uso.

## Instalacion local

### Linux/Mac

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### Windows

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

La API queda disponible en:

```text
http://localhost:8000
```

Swagger queda disponible en:

```text
http://localhost:8000/docs
```

## Docker Compose

Desde la raiz del proyecto:

```bash
docker compose up --build
```

## Endpoints principales

```text
GET    /health
GET    /ready
POST   /documents/upload
GET    /documents
GET    /documents/{document_id}
DELETE /documents/{document_id}
POST   /documents/{document_id}/analyze
GET    /documents/{document_id}/analysis
POST   /documents/{document_id}/reprocess
GET    /analytics/usage
```

## Flujo de uso

1. Subir un PDF desde Swagger usando `POST /documents/upload`.
2. Analizar el documento con `POST /documents/{document_id}/analyze`.
3. Consultar el resultado con `GET /documents/{document_id}/analysis`.
4. Consultar metricas con `GET /analytics/usage`.

## Calidad

```bash
ruff check .
ruff format .
```
