# TAREA CODEX — Validación completa + mejora visual del MVP local

Proyecto: `ai-document-intelligence-hub`

Objetivo: validar que el MVP local funciona de punta a punta y mejorar el frontend local sin avanzar todavía a Azure.

No rehagas el backend desde cero. No avances a Fase 2/Azure. Solo corrige errores mínimos si impiden validar el MVP local.

---

## 1. Contexto actual

El backend ya levanta con Docker Compose en:

```text
http://localhost:8000
```

El frontend ya levanta con Vite/pnpm en:

```text
http://localhost:5173
```

Endpoints existentes del backend:

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

---

## 2. Reglas

- No implementar Azure todavía.
- No añadir autenticación todavía.
- No cambiar nombres de endpoints.
- No romper Docker Compose.
- No romper Swagger.
- No borrar funcionalidades ya existentes.
- Mantener FastAPI + React/Vite + pnpm.
- Corregir solo lo necesario para que el MVP local funcione estable.

---

## 3. Validación técnica obligatoria

Ejecuta y documenta resultado de estos comandos.

### 3.1 Backend con Docker

Desde la raíz del proyecto:

```powershell
docker compose up --build -d
docker compose ps
```

Comprobar:

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/health" -Method GET
Invoke-RestMethod -Uri "http://localhost:8000/ready" -Method GET
Invoke-RestMethod -Uri "http://localhost:8000/documents" -Method GET
Invoke-RestMethod -Uri "http://localhost:8000/analytics/usage" -Method GET
```

Debe responder correctamente.

### 3.2 Backend tests/lint

Desde `backend/`:

```powershell
pytest
ruff check .
```

Si `ruff check .` detecta errores simples, corrígelos. Si detecta algo no crítico, explícalo.

### 3.3 Frontend

Desde `frontend/`:

```powershell
node --version
pnpm --version
pnpm install
pnpm build
```

Debe compilar sin errores.

---

## 4. Añadir prueba E2E local desde el frontend

Añade una sección visible en el frontend llamada:

```text
Validación MVP local
```

Debe tener un botón:

```text
Ejecutar prueba completa
```

Al pulsar, el frontend debe ejecutar automáticamente este flujo:

1. Llamar a `GET /health`.
2. Llamar a `GET /ready`.
3. Generar un PDF de prueba con `jspdf`.
4. Subirlo a `POST /documents/upload`.
5. Guardar el `document_id` recibido.
6. Llamar a `GET /documents` y comprobar que aparece el documento.
7. Llamar a `POST /documents/{document_id}/analyze`.
8. Llamar a `GET /documents/{document_id}/analysis`.
9. Llamar a `GET /analytics/usage`.
10. Mostrar resultado final:

```text
✅ MVP local validado correctamente
```

o, si falla:

```text
❌ Error en paso X: mensaje del error
```

### PDF de prueba

El PDF generado debe llamarse:

```text
factura_riesgo_prueba.pdf
```

Debe contener texto suficiente para activar el mock:

```text
Factura de prueba
Contrato de servicios
Este documento contiene un posible riesgo operativo.
Importe total: 100 euros.
Cliente: Empresa Demo SL.
```

### Resultado visual esperado

La sección debe mostrar una lista de pasos con estados:

```text
Health: pendiente / ok / error
Ready: pendiente / ok / error
Generar PDF: pendiente / ok / error
Subir documento: pendiente / ok / error
Listar documentos: pendiente / ok / error
Analizar documento: pendiente / ok / error
Consultar análisis: pendiente / ok / error
Analytics: pendiente / ok / error
```

---

## 5. Mejoras visuales del frontend

Mejora el diseño actual sin añadir librerías pesadas.

Mantener CSS propio en `frontend/src/styles.css`.

### 5.1 Correcciones de texto

Corrige acentos y textos:

- `Analisis` → `Análisis`
- `analisis` → `análisis`
- `metricas` → `métricas`
- `backend fastAPI` → `backend FastAPI`
- `Ningun archivo seleccionado` → `Ningún archivo seleccionado`
- `Ver analisis` → `Ver análisis`

### 5.2 Layout

Mejorar:

- ancho máximo centrado;
- tarjetas con mejor padding;
- separación vertical coherente;
- botones con estados hover;
- tabla más legible;
- diseño responsive;
- zona de análisis más visible.

### 5.3 Estado seleccionado

Cuando se seleccione un documento, mostrar arriba del panel de análisis:

```text
Documento seleccionado: #ID — nombre.pdf — estado
```

En la tabla, la fila seleccionada debe quedar resaltada.

### 5.4 Badges de estado

Mostrar badges visuales para estados:

- `uploaded`
- `processing`
- `processed`
- `failed`
- `deleted`

### 5.5 Mensajes de carga y error

Añadir estados claros:

- `Cargando...`
- `Subiendo documento...`
- `Analizando documento...`
- `Error: ...`
- `Operación completada correctamente`

### 5.6 JSON legible

Las respuestas JSON deben mostrarse en bloques `<pre>` con scroll horizontal si hace falta.

---

## 6. Ajustes backend permitidos si hacen falta

Solo si es necesario:

### 6.1 CORS

Confirmar que el backend permite llamadas desde:

```text
http://localhost:5173
http://127.0.0.1:5173
```

No usar `allow_origins=["*"]` si no es necesario.

### 6.2 Errores documentados

Si es sencillo, mejorar los errores HTTP para que sean claros:

- archivo no PDF → `400 Only PDF files are allowed.`
- documento no encontrado → `404 Document not found.`
- análisis no encontrado → `404 Analysis not found.`
- PDF corrupto/sin texto → `400 Could not extract text from PDF.`

No es obligatorio modificar OpenAPI en esta tarea.

---

## 7. Archivos que probablemente modificarás

Frontend:

```text
frontend/src/App.tsx
frontend/src/styles.css
frontend/src/api/client.ts
frontend/src/utils/createTestPdf.ts
frontend/src/components/*.tsx
```

Backend, solo si hace falta:

```text
backend/app/main.py
backend/app/api/*.py
backend/app/services/*.py
```

---

## 8. Criterios de aceptación

La tarea está completada cuando:

- `docker compose up --build -d` deja el backend corriendo.
- `/health` responde OK.
- `/ready` responde OK.
- `GET /documents` responde OK.
- `GET /analytics/usage` responde OK.
- `pytest` pasa o se explican/corrigen fallos reales.
- `ruff check .` pasa o se corrigen errores simples.
- `pnpm install` funciona.
- `pnpm build` funciona.
- El frontend abre en `http://localhost:5173`.
- El botón `Ejecutar prueba completa` valida el flujo entero.
- Se puede subir un PDF manualmente.
- Se puede generar PDF de prueba.
- Se puede listar documentos.
- Se puede seleccionar documento.
- Se puede analizar documento.
- Se puede ver análisis.
- Se puede ver analytics.
- El diseño queda más limpio, legible y presentable.

---

## 9. Resultado final que debes entregar

Al terminar, responde con:

```text
1. Comandos ejecutados y resultado.
2. Archivos modificados.
3. Estado de backend.
4. Estado de frontend.
5. Resultado de pytest.
6. Resultado de ruff.
7. Resultado de pnpm build.
8. Resultado de la prueba E2E local.
9. Errores encontrados y cómo se corrigieron.
10. Si el MVP queda listo para pasar a Fase 2 Azure Container Apps.
```

---

## 10. No hacer todavía

No implementar todavía:

- Azure Container Apps.
- Azure Container Registry.
- Blob Storage.
- Azure SQL.
- Azure OpenAI.
- Key Vault.
- Managed Identity.
- Bicep.
- GitHub Actions de despliegue cloud.
- API Management.
- Azure AI Search.

Eso será Fase 2 y siguientes.
