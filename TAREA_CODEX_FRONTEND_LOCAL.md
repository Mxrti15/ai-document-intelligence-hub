# TAREA PARA CODEX — Crear frontend local con pnpm para AI Document Intelligence Hub

## Contexto del proyecto

Estamos dentro del repositorio:

```text
ai-document-intelligence-hub
```

Ya existe un backend con FastAPI y Docker Compose.

El backend responde correctamente en:

```text
http://localhost:8000
```

Endpoints existentes:

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

Objetivo de esta tarea:

Crear un frontend local con React + Vite + TypeScript usando `pnpm`, para poder probar el MVP desde navegador en:

```text
http://localhost:5173
```

---

# Reglas obligatorias para Codex

1. No tocar Azure.
2. No modificar la arquitectura cloud.
3. No rehacer el backend.
4. No borrar endpoints existentes.
5. Solo modificar el backend si hace falta añadir CORS para permitir llamadas desde `http://localhost:5173`.
6. No usar Tailwind ni librerías UI externas.
7. Usar React + Vite + TypeScript.
8. Usar `pnpm`.
9. Crear una interfaz funcional, simple y clara.
10. Al final, comprobar instalación, build y conexión real con backend.
11. Si un comando queda bloqueado porque levanta un servidor en primer plano, usar una alternativa en background o indicar claramente el comando que debe ejecutar el usuario.
12. No hacer commits automáticamente salvo que se indique.

---

# Objetivo funcional del frontend

El frontend debe permitir:

1. Comprobar estado del backend:
   - `/health`
   - `/ready`

2. Generar un PDF de prueba desde el navegador.

3. Subir un PDF al backend:
   - `POST /documents/upload`

4. Listar documentos:
   - `GET /documents`

5. Seleccionar un documento.

6. Analizar documento:
   - `POST /documents/{document_id}/analyze`

7. Consultar análisis:
   - `GET /documents/{document_id}/analysis`

8. Reprocesar documento:
   - `POST /documents/{document_id}/reprocess`

9. Ver métricas:
   - `GET /analytics/usage`

---

# 1. Comprobación inicial del entorno

Ejecuta desde la raíz del proyecto:

```powershell
git status
docker compose ps
docker compose up --build -d
```

Comprueba backend:

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/health" -Method GET | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8000/ready" -Method GET | ConvertTo-Json
```

Comprueba Node y pnpm:

```powershell
node --version
pnpm --version
```

Si `pnpm` no existe, intenta:

```powershell
corepack enable
corepack prepare pnpm@latest --activate
pnpm --version
```

Si sigue fallando, no instales herramientas raras sin avisar. Informa claramente de qué falta.

---

# 2. Crear carpeta frontend

Crear esta estructura:

```text
frontend/
├── index.html
├── package.json
├── tsconfig.json
├── tsconfig.node.json
├── vite.config.ts
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── styles.css
│   ├── api/
│   │   └── client.ts
│   ├── components/
│   │   ├── StatusPanel.tsx
│   │   ├── UploadPanel.tsx
│   │   ├── DocumentsPanel.tsx
│   │   ├── AnalysisPanel.tsx
│   │   └── AnalyticsPanel.tsx
│   └── utils/
│       └── createTestPdf.ts
```

---

# 3. package.json

Crear `frontend/package.json`:

```json
{
  "name": "ai-document-intelligence-hub-frontend",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "tsc && vite build",
    "preview": "vite preview --host 0.0.0.0",
    "lint": "tsc --noEmit"
  },
  "dependencies": {
    "@vitejs/plugin-react": "latest",
    "vite": "latest",
    "typescript": "latest",
    "react": "latest",
    "react-dom": "latest",
    "jspdf": "latest"
  },
  "devDependencies": {}
}
```

---

# 4. Configuración de TypeScript

Crear `frontend/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["DOM", "DOM.Iterable", "ES2020"],
    "allowJs": false,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "module": "ESNext",
    "moduleResolution": "Node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx"
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

Crear `frontend/tsconfig.node.json`:

```json
{
  "compilerOptions": {
    "composite": true,
    "module": "ESNext",
    "moduleResolution": "Node",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
```

---

# 5. Vite config

Crear `frontend/vite.config.ts`:

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 5173
  }
});
```

---

# 6. index.html

Crear `frontend/index.html`:

```html
<!doctype html>
<html lang="es">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>AI Document Intelligence Hub</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

---

# 7. Cliente API

Crear `frontend/src/api/client.ts`.

Debe usar:

```ts
const API_BASE_URL = "http://localhost:8000";
```

Implementar:

```ts
export async function checkHealth()
export async function checkReady()
export async function uploadDocument(file: File)
export async function listDocuments()
export async function getDocument(documentId: number)
export async function deleteDocument(documentId: number)
export async function analyzeDocument(documentId: number)
export async function getDocumentAnalysis(documentId: number)
export async function reprocessDocument(documentId: number)
export async function getUsageAnalytics()
```

Requisitos:

- Todas las llamadas usan `fetch`.
- Si la respuesta no es `ok`, lanzar error con mensaje útil.
- Si el backend devuelve `{ "detail": "..." }`, mostrar ese `detail`.
- `uploadDocument(file)` debe usar `FormData`.
- No usar Axios.

Ejemplo de helper:

```ts
async function handleResponse<T>(response: Response): Promise<T> {
  const data = await response.json().catch(() => null);

  if (!response.ok) {
    const message =
      data?.detail ||
      data?.message ||
      `Request failed with status ${response.status}`;

    throw new Error(message);
  }

  return data as T;
}
```

---

# 8. Generador de PDF de prueba

Crear `frontend/src/utils/createTestPdf.ts`.

Debe usar `jspdf`.

Debe exportar:

```ts
export function createTestPdfFile(): File
```

El PDF debe llamarse:

```text
factura_riesgo_prueba.pdf
```

El PDF debe contener texto suficiente para que el backend lo pueda analizar:

```text
Factura de prueba
Contrato de servicios
Este documento contiene un posible riesgo operativo.
Importe total: 100 euros.
Cliente: Empresa Demo SL.
Proveedor: SecOps Demo Provider.
Fecha: 14/05/2026.
```

Objetivo:

- Si el backend detecta `factura`, debería clasificar como `invoice`.
- Si detecta `contrato`, podría clasificar como `contract` según prioridad.
- Si detecta `riesgo`, debería marcar `risk_level = medium`.

---

# 9. Componentes de UI

Crear estos componentes:

```text
StatusPanel.tsx
UploadPanel.tsx
DocumentsPanel.tsx
AnalysisPanel.tsx
AnalyticsPanel.tsx
```

## 9.1 StatusPanel

Debe tener botones:

```text
Comprobar health
Comprobar ready
```

Debe mostrar la respuesta JSON.

## 9.2 UploadPanel

Debe permitir:

- seleccionar PDF manualmente;
- generar PDF de prueba;
- mostrar nombre del archivo seleccionado;
- subir documento.

Botones:

```text
Generar PDF de prueba
Subir documento
```

Al subir correctamente, debe devolver el documento creado y avisar al padre para actualizar lista.

## 9.3 DocumentsPanel

Debe:

- listar documentos;
- mostrar ID, nombre, estado y fecha;
- permitir seleccionar documento;
- permitir eliminar documento;
- resaltar documento seleccionado.

Botones:

```text
Actualizar lista
Seleccionar
Eliminar
```

## 9.4 AnalysisPanel

Debe:

- mostrar documento seleccionado;
- analizar documento;
- consultar análisis;
- reprocesar documento;
- mostrar JSON formateado.

Botones:

```text
Analizar documento
Ver análisis
Reprocesar
```

## 9.5 AnalyticsPanel

Debe:

- llamar a `/analytics/usage`;
- mostrar JSON formateado;
- mostrar tarjetas simples con:
  - documentos subidos;
  - documentos procesados;
  - documentos fallidos;
  - tokens totales;
  - coste estimado.

---

# 10. App principal

Crear `frontend/src/App.tsx`.

Debe:

- mantener estado global mínimo:
  - documento seleccionado;
  - último documento subido;
  - lista de documentos;
  - mensajes de error;
- renderizar los paneles;
- permitir flujo completo sin recargar página.

Layout sugerido:

```text
Título
Descripción breve

[Estado Backend]

[Subida de documento]  [Analytics]

[Documentos]

[Análisis]
```

No hace falta diseño perfecto, pero debe ser cómodo.

---

# 11. main.tsx

Crear `frontend/src/main.tsx`:

```tsx
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

---

# 12. Estilos

Crear `frontend/src/styles.css`.

Diseño simple:

- fondo gris claro;
- tarjetas blancas;
- botones visibles;
- mensajes de error en rojo;
- mensajes OK en verde;
- JSON en bloques `<pre>`;
- responsive;
- sin Tailwind.

---

# 13. CORS en backend

Si el frontend no puede llamar al backend por CORS, modificar `backend/app/main.py`.

Añadir:

```python
from fastapi.middleware.cors import CORSMiddleware
```

Y después de crear `app`:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

No usar `allow_origins=["*"]` salvo que sea estrictamente necesario para una prueba local.

---

# 14. Instalación y build

Ejecutar:

```powershell
cd frontend
pnpm install
pnpm build
```

Si falla, corregir errores de TypeScript o imports.

También ejecutar:

```powershell
pnpm lint
```

Si falla por tipados simples, corregir.

---

# 15. Levantar backend y frontend

Desde raíz del proyecto, levantar backend:

```powershell
docker compose up --build -d
```

Comprobar:

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/health" -Method GET | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8000/ready" -Method GET | ConvertTo-Json
```

Levantar frontend:

```powershell
cd frontend
pnpm dev
```

Si Codex no puede dejarlo corriendo porque el comando bloquea la terminal, indicarme que debo ejecutarlo yo manualmente.

URL esperada:

```text
http://localhost:5173
```

---

# 16. Prueba funcional obligatoria

Con backend y frontend levantados, validar este flujo desde el navegador:

1. Abrir:

```text
http://localhost:5173
```

2. Pulsar:

```text
Comprobar health
```

Debe devolver `status: ok`.

3. Pulsar:

```text
Comprobar ready
```

Debe devolver `status: ready`.

4. Pulsar:

```text
Generar PDF de prueba
```

Debe seleccionar automáticamente `factura_riesgo_prueba.pdf`.

5. Pulsar:

```text
Subir documento
```

Debe crear un documento en backend.

6. Pulsar:

```text
Actualizar lista
```

Debe aparecer el documento.

7. Seleccionar documento.

8. Pulsar:

```text
Analizar documento
```

Debe ejecutar análisis mock.

9. Pulsar:

```text
Ver análisis
```

Debe mostrar JSON con resumen, tipo de documento y risk level.

10. Pulsar:

```text
Ver analytics
```

Debe mostrar contadores actualizados.

---

# 17. Validación alternativa por PowerShell

Si no se puede probar visualmente desde Codex, hacer al menos:

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/health" -Method GET | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8000/ready" -Method GET | ConvertTo-Json
```

Y comprobar que:

```powershell
cd frontend
pnpm build
```

funciona sin errores.

---

# 18. Resultado final esperado

Al terminar, responder con esta tabla:

```text
| Comprobación | Resultado |
|---|---|
| git status revisado | sí/no |
| backend levantado con Docker | sí/no |
| /health responde | sí/no |
| /ready responde | sí/no |
| node detectado | versión |
| pnpm detectado | versión |
| frontend creado | sí/no |
| pnpm install | ok/error |
| pnpm build | ok/error |
| CORS añadido | sí/no/no hacía falta |
| URL frontend | http://localhost:5173 |
```

También listar:

```text
Archivos creados:
- ...

Archivos modificados:
- ...

Errores encontrados:
- ...

Cómo se resolvieron:
- ...
```

---

# 19. Criterios de aceptación finales

La tarea se considera terminada solo si:

- Existe carpeta `frontend`.
- `pnpm install` funciona.
- `pnpm build` funciona.
- El backend sigue respondiendo.
- El frontend se puede abrir en `http://localhost:5173`.
- Se puede generar un PDF de prueba desde la UI.
- Se puede subir el PDF.
- Se puede listar el documento.
- Se puede analizar.
- Se puede ver el análisis.
- Se puede ver analytics.
- No se ha tocado Azure.
- No se ha roto Docker Compose.

---

# 20. Prompt corto para ejecutar esta tarea

Puedes pegarle a Codex esto:

```text
Lee el archivo TAREA_CODEX_FRONTEND_LOCAL.md y ejecútalo completo.

Crea un frontend local con React + Vite + TypeScript usando pnpm para probar el backend de AI Document Intelligence Hub desde http://localhost:5173.

Debe permitir health, ready, generar PDF de prueba, subir PDF, listar documentos, seleccionar documento, analizarlo, ver análisis y ver analytics.

Comprueba node, pnpm, docker compose, backend health/ready, pnpm install y pnpm build.

Si hace falta, añade CORS al backend.

No avances a Azure y no rehagas el backend.
```
