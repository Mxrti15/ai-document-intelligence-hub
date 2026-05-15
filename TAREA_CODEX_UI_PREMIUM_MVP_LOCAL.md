# TAREA CODEX — Mejora espectacular de interfaz MVP local

## Contexto

Proyecto: `AI Document Intelligence Hub`

Ya existe:

- Backend FastAPI en Docker.
- Frontend React + Vite + TypeScript con pnpm.
- Flujo funcional:
  - `/health`
  - `/ready`
  - generar PDF de prueba
  - subir PDF
  - listar documentos
  - seleccionar documento
  - analizar documento
  - ver análisis
  - ver analytics

El objetivo de esta tarea es **mejorar mucho la interfaz visual y la experiencia de usuario**, sin rehacer el backend ni cambiar la arquitectura.

---

# Objetivo principal

Convertir el frontend actual en una demo visualmente potente, limpia y presentable para portfolio/LinkedIn/entrevista.

Debe seguir siendo una consola local MVP, pero con aspecto mucho más profesional:

- diseño moderno;
- dashboard claro;
- tarjetas elegantes;
- estados visuales;
- tabla de documentos cuidada;
- panel de análisis bonito;
- flujo guiado;
- métricas visibles;
- botones coherentes;
- responsive básico;
- sin romper ninguna funcionalidad existente.

---

# Restricciones importantes

## No hacer

- No avances a Azure.
- No cambies endpoints del backend.
- No rehagas el backend.
- No rompas el cliente API existente.
- No elimines funcionalidades actuales.
- No uses Tailwind si el proyecto no lo tiene ya configurado.
- No añadas una librería UI pesada.
- No metas autenticación.
- No metas RAG.
- No metas Azure OpenAI.
- No metas Blob Storage.

## Sí puedes hacer

- Reorganizar componentes React.
- Mejorar `App.tsx`.
- Mejorar `styles.css`.
- Crear componentes nuevos si ayuda.
- Añadir pequeños helpers de UI.
- Añadir estados `loading`, `success`, `error`.
- Mejorar textos, badges, layout y visualización JSON.
- Añadir una prueba visual guiada del MVP.
- Añadir iconos simples usando Unicode/emoji o CSS.
- Añadir dependencias ligeras solo si son realmente necesarias, pero prioriza CSS propio.

---

# Estado actual esperado

El frontend está en:

```text
frontend/
├── src/
│   ├── App.tsx
│   ├── styles.css
│   ├── api/client.ts
│   ├── components/
│   └── utils/createTestPdf.ts
```

Mantener Vite en:

```text
http://localhost:5173
```

Backend:

```text
http://localhost:8000
```

---

# 1. Revisión previa

Antes de modificar, revisa:

```bash
cd frontend
pnpm install
pnpm build
```

Desde la raíz comprueba backend:

```bash
docker compose up --build -d
```

Y comprueba:

```text
http://localhost:8000/health
http://localhost:8000/ready
```

---

# 2. Rediseño visual general

## Estilo deseado

Crear un look tipo SaaS cloud/AI dashboard:

- fondo con degradado suave;
- contenedor central ancho;
- header grande;
- subtitle profesional;
- chip de estado `MVP LOCAL`;
- tarjetas con bordes suaves;
- sombras ligeras;
- botones modernos;
- tabla limpia;
- badges de estado;
- panel de análisis más visual;
- JSON formateado bonito;
- layout responsive.

Inspiración visual:

```text
Azure + AI + dashboard enterprise + FastAPI console
```

Colores sugeridos:

```text
Fondo: #eef4f8 / #f8fafc
Texto principal: #0f172a
Texto secundario: #64748b
Azul principal: #2563eb
Azul oscuro: #1e40af
Verde éxito: #16a34a
Amarillo pendiente: #ca8a04
Rojo error: #dc2626
Bordes: #dbe3ea
Card: rgba(255,255,255,0.88)
```

No es obligatorio usar exactamente estos colores, pero mantener una estética profesional.

---

# 3. Nueva estructura visual recomendada

La pantalla debe organizarse así:

```text
Header
 ├─ Chip MVP LOCAL
 ├─ Título
 ├─ Descripción
 └─ Resumen rápido del estado

Panel de validación MVP
 ├─ 8 pasos del flujo
 └─ Botón "Ejecutar prueba completa"

Grid principal
 ├─ Estado Backend
 ├─ Subida de documento
 └─ Analytics resumido

Panel Documentos
 ├─ Tabla de documentos
 └─ Detalle documento seleccionado

Panel Análisis
 ├─ Acciones
 ├─ Resultado interpretado
 └─ JSON técnico colapsable o formateado
```

---

# 4. Header premium

Crear un header más potente.

Debe mostrar:

```text
MVP LOCAL
AI Document Intelligence Hub
Consola local para validar subida, análisis mock y métricas del backend FastAPI antes de desplegar en Azure.
```

Añadir pequeños badges:

```text
FastAPI
Docker
React
SQLite
Mock AI
```

Añadir mini resumen:

```text
Backend: online/offline
Documentos: X
Procesados: Y
Fallidos: Z
```

Si aún no hay datos cargados, mostrar `—`.

---

# 5. Panel “Validación MVP local”

Mejorar la sección actual de validación.

Debe mostrar pasos como tarjetas pequeñas:

1. Health
2. Ready
3. Generar PDF
4. Subir documento
5. Listar documentos
6. Analizar documento
7. Consultar análisis
8. Analytics

Cada paso debe tener estado visual:

```text
pendiente
ejecutando
ok
error
```

Con colores:

- pendiente: gris/azul claro
- ejecutando: amarillo
- ok: verde
- error: rojo

Botón principal:

```text
Ejecutar prueba completa
```

Durante la ejecución:

- desactivar botón;
- mostrar texto `Ejecutando...`;
- actualizar pasos en tiempo real;
- mostrar error claro si falla.

---

# 6. Panel Estado Backend

Mejorar tarjeta de backend.

Debe tener:

- botón `Comprobar health`;
- botón `Comprobar ready`;
- indicador visual:
  - online;
  - offline;
  - pendiente.
- último JSON recibido.

Ejemplo visual:

```text
Estado Backend
● Online
FastAPI responde correctamente

[Comprobar health] [Comprobar ready]
```

---

# 7. Panel Subida de documento

Mejorar la UX.

Debe incluir:

- zona tipo drag/drop visual, aunque solo use input file normal;
- texto:
  - `Selecciona un PDF o genera uno de prueba`;
- botón `Generar PDF demo`;
- botón `Subir PDF`;
- nombre del archivo seleccionado;
- tamaño del archivo;
- estado de subida;
- respuesta resumida después de subir.

Cuando se genere PDF de prueba, mostrar:

```text
factura_riesgo_prueba.pdf listo para subir
```

Cuando se suba:

```text
Documento subido correctamente — ID #X
```

---

# 8. Panel Analytics

Mejorar tarjeta de analytics.

Debe mostrar métricas como cards pequeñas:

```text
Subidos
Procesados
Fallidos
Tokens
Coste estimado
```

Con números grandes.

Ejemplo:

```text
14
documentos subidos
```

Botón:

```text
Actualizar analytics
```

Si tokens/coste son 0, mostrar un tooltip/texto pequeño:

```text
Todavía usando análisis mock, sin coste real de IA.
```

---

# 9. Panel Documentos

Mejorar tabla.

Columnas:

- ID
- Nombre
- Estado
- Fecha
- Acciones

Estados con badges:

```text
uploaded  -> azul
processing -> amarillo
processed -> verde
failed -> rojo
deleted -> gris
```

Acciones:

- `Seleccionar`
- `Eliminar`

Al seleccionar un documento:

- resaltar fila;
- mostrar detalle lateral o debajo:

```text
Documento seleccionado
ID
Nombre
Estado
Storage path
Tamaño
Fecha
```

Si no hay documentos:

Mostrar empty state:

```text
Aún no hay documentos. Genera un PDF de prueba y súbelo para empezar.
```

---

# 10. Panel Análisis

Mejorar mucho este panel.

Debe mostrar:

- documento seleccionado;
- botones:
  - `Analizar documento`
  - `Ver análisis`
  - `Reprocesar`
- estado actual;
- resultado interpretado.

Si hay análisis, mostrar tarjetas:

```text
Tipo: invoice
Riesgo: medium
Idioma: es
Resumen: ...
```

Badges:

- `invoice`
- `contract`
- `cv`
- `unknown`

Riesgo:

- `low` verde
- `medium` amarillo
- `high` rojo

También mostrar JSON técnico en `<pre>` con buen estilo.

Si no hay documento seleccionado:

```text
Selecciona un documento de la tabla para analizarlo.
```

---

# 11. Mejorar mensajes de error

Los errores deben verse en una alerta visual clara:

```text
No se pudo subir el documento: Only PDF files are allowed.
```

Crear un componente o helper si hace falta:

```text
SuccessAlert
ErrorAlert
InfoAlert
```

Pero no hace falta sobrearquitectura.

---

# 12. Mejorar `App.tsx`

Refactoriza si es necesario, pero sin sobrecomplicar.

Debe mantener:

- estados de backend;
- archivo seleccionado;
- documento seleccionado;
- lista de documentos;
- resultado de análisis;
- analytics;
- validación completa.

Puede quedar todo en `App.tsx` si el tamaño sigue siendo razonable.

Si prefieres componentes, usa:

```text
components/
├── Header.tsx
├── ValidationPanel.tsx
├── BackendStatusCard.tsx
├── UploadCard.tsx
├── AnalyticsCard.tsx
├── DocumentsTable.tsx
├── AnalysisCard.tsx
├── JsonBlock.tsx
└── Badge.tsx
```

No es obligatorio crear todos, pero sí recomendable si mejora claridad.

---

# 13. Mejorar `styles.css`

Crear CSS profesional.

Debe incluir:

- variables CSS en `:root`;
- reset básico;
- layout responsive;
- cards;
- buttons;
- badges;
- tables;
- JSON block;
- loading states;
- empty states.

Ejemplo de clases esperadas:

```text
.app-shell
.hero
.hero-badge
.hero-title
hero-subtitle
.card
.card-header
.grid
.button
.button-primary
.button-secondary
.button-danger
.badge
.badge-success
.badge-warning
.badge-error
.table
.json-block
.alert
.validation-grid
.metric-card
```

---

# 14. Añadir prueba completa desde UI

El botón `Ejecutar prueba completa` debe:

1. llamar `/health`;
2. llamar `/ready`;
3. generar PDF de prueba;
4. subir PDF;
5. listar documentos;
6. seleccionar el documento recién subido;
7. analizar documento;
8. consultar análisis;
9. consultar analytics.

Debe actualizar visualmente cada paso.

Al terminar mostrar:

```text
Validación completada correctamente.
```

Si falla:

```text
Validación fallida en el paso X: mensaje del error
```

---

# 15. Validación técnica

Al finalizar, ejecutar:

```bash
cd frontend
pnpm install
pnpm build
```

Desde raíz:

```bash
docker compose up --build -d
docker compose exec backend python -m pytest
docker compose exec backend python -m ruff check .
```

Comprobar que el frontend sigue pudiendo llamar al backend.

---

# 16. Criterios de aceptación

La tarea se considera completada si:

- El frontend se ve mucho más profesional.
- `pnpm build` pasa.
- `pytest` pasa.
- `ruff check .` pasa.
- La prueba completa desde la UI funciona.
- El usuario puede probar todo sin Swagger.
- El flujo:
  - health;
  - ready;
  - generar PDF;
  - subir;
  - listar;
  - seleccionar;
  - analizar;
  - ver análisis;
  - analytics;
  funciona desde la interfaz.
- No se ha avanzado a Azure.
- No se ha roto Docker Compose.
- No se han cambiado endpoints del backend.

---

# 17. Resultado esperado al terminar

Al terminar, responde con:

```text
UI mejorada correctamente.

Comprobaciones:
- pnpm install: OK/ERROR
- pnpm build: OK/ERROR
- docker compose up: OK/ERROR
- pytest: OK/ERROR
- ruff: OK/ERROR
- flujo completo UI: OK/ERROR

Archivos modificados:
- ...
Notas:
- ...
```

---

# Prompt recomendado para ejecutar esta tarea

```text
Lee el archivo TAREA_CODEX_UI_PREMIUM_MVP_LOCAL.md y ejecútalo completo.

Objetivo: mejorar espectacularmente la interfaz del frontend local del proyecto AI Document Intelligence Hub, sin tocar Azure ni rehacer el backend.

Mantén el flujo funcional actual y conviértelo en una demo visual de portfolio: dashboard moderno, panel de validación, subida PDF, tabla de documentos, análisis visual, analytics y prueba completa desde UI.

Al finalizar ejecuta pnpm build, pytest y ruff check dentro del contenedor backend.
```
