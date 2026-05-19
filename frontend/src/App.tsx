import { useEffect, useMemo, useState } from "react";
import {
  DocumentRecord,
  UsageAnalytics,
  checkHealth,
  getUsageAnalytics,
  listDocuments
} from "./api/client";
import { AnalysisPanel } from "./components/AnalysisPanel";
import { AnalyticsPanel } from "./components/AnalyticsPanel";
import { DocumentsPanel } from "./components/DocumentsPanel";
import { RagPanel } from "./components/RagPanel";
import { StatusPanel } from "./components/StatusPanel";
import { UploadPanel } from "./components/UploadPanel";
import { ValidationPanel } from "./components/ValidationPanel";

export type BackendState = "pending" | "online" | "offline";

const productCapabilities = [
  {
    title: "Subida de documentos",
    copy: "Carga PDFs empresariales o genera una factura demo para probar el flujo completo."
  },
  {
    title: "Analisis inteligente",
    copy: "El backend clasifica el documento, resume el contenido y detecta senales de riesgo."
  },
  {
    title: "Resultado estructurado",
    copy: "Convierte texto no estructurado en datos clave, etiquetas, riesgo y metricas de uso."
  }
];

const flowSteps = [
  "PDF",
  "Extraccion de texto",
  "Clasificacion IA",
  "Resumen, datos y riesgo",
  "Metricas"
];

export default function App() {
  const [documents, setDocuments] = useState<DocumentRecord[]>([]);
  const [selectedDocument, setSelectedDocument] = useState<DocumentRecord | null>(null);
  const [lastUploaded, setLastUploaded] = useState<DocumentRecord | null>(null);
  const [analytics, setAnalytics] = useState<UsageAnalytics | null>(null);
  const [backendState, setBackendState] = useState<BackendState>("pending");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const processedDocuments = useMemo(
    () => documents.filter((document) => document.status === "processed").length,
    [documents]
  );

  const failedDocuments = useMemo(
    () => documents.filter((document) => document.status === "failed").length,
    [documents]
  );

  async function refreshDocuments() {
    try {
      const data = await listDocuments();
      setDocuments(data.documents);
      setError(null);
      return data;
    } catch (refreshError) {
      const errorMessage =
        refreshError instanceof Error ? refreshError.message : "No se pudo actualizar la lista.";
      setError(errorMessage);
      throw refreshError;
    }
  }

  async function refreshAnalytics() {
    try {
      const data = await getUsageAnalytics();
      setAnalytics(data);
      setError(null);
      return data;
    } catch (analyticsError) {
      const errorMessage =
        analyticsError instanceof Error ? analyticsError.message : "No se pudieron cargar las metricas.";
      setError(errorMessage);
      throw analyticsError;
    }
  }

  async function refreshDashboard() {
    await Promise.allSettled([refreshDocuments(), refreshAnalytics()]);
  }

  function handleUploaded(document: DocumentRecord) {
    setLastUploaded(document);
    setSelectedDocument(document);
    setMessage(`Documento subido correctamente - ID #${document.id}`);
    void refreshDashboard();
  }

  function handleDeleted() {
    setSelectedDocument(null);
    setMessage("Documento eliminado.");
    void refreshDashboard();
  }

  function handleError(errorMessage: string) {
    setError(errorMessage);
    setMessage(null);
  }

  useEffect(() => {
    async function loadInitialData() {
      await refreshDashboard();

      try {
        await checkHealth();
        setBackendState("online");
      } catch {
        setBackendState("offline");
      }
    }

    void loadInitialData();
  }, []);

  return (
    <main className="app-shell">
      <header className="hero">
        <div className="hero-copy">
          <span className="hero-badge">Document AI demo</span>
          <h1>AI Document Intelligence Hub</h1>
          <p className="hero-subtitle">
            Convierte documentos empresariales en resumenes, datos clave y alertas de riesgo con IA.
          </p>
          <div className="tech-stack" aria-label="Tecnologias">
            <span>FastAPI</span>
            <span>Docker</span>
            <span>React</span>
            <span>SQLite</span>
            <span>Mock AI</span>
            <span>Azure-ready</span>
          </div>
        </div>

        <div className="hero-summary" aria-label="Resumen del MVP">
          <div>
            <span>Backend</span>
            <strong className={`summary-status summary-${backendState}`}>{backendState}</strong>
          </div>
          <div>
            <span>Documentos</span>
            <strong>{(analytics?.documents_uploaded ?? documents.length) || "--"}</strong>
          </div>
          <div>
            <span>Procesados</span>
            <strong>{(analytics?.documents_processed ?? processedDocuments) || "--"}</strong>
          </div>
          <div>
            <span>Fallidos</span>
            <strong>{(analytics?.documents_failed ?? failedDocuments) || "--"}</strong>
          </div>
        </div>
      </header>

      <section className="product-section panel-wide">
        <div className="section-heading">
          <span className="section-kicker">Producto</span>
          <h2>Que hace este proyecto</h2>
        </div>
        <div className="capability-grid">
          {productCapabilities.map((capability) => (
            <article className="capability-card" key={capability.title}>
              <strong>{capability.title}</strong>
              <p>{capability.copy}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="card panel-wide flow-section">
        <div className="section-heading">
          <span className="section-kicker">Pipeline documental</span>
          <h2>Del PDF a inteligencia accionable</h2>
        </div>
        <div className="flow-track" aria-label="Flujo visual del documento">
          {flowSteps.map((step, index) => (
            <div className="flow-step" key={step}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              <strong>{step}</strong>
            </div>
          ))}
        </div>
      </section>

      {error ? <div className="alert alert-error">{error}</div> : null}
      {message ? <div className="alert alert-ok">{message}</div> : null}
      {lastUploaded ? (
        <div className="alert alert-info">Ultimo documento listo: #{lastUploaded.id}</div>
      ) : null}

      <ValidationPanel
        onBackendStateChange={setBackendState}
        onCompleted={refreshDashboard}
        onDocumentSelected={setSelectedDocument}
      />

      <div className="workspace-grid">
        <UploadPanel onError={handleError} onUploaded={handleUploaded} />
      </div>

      <DocumentsPanel
        documents={documents}
        selectedDocument={selectedDocument}
        onDeleted={handleDeleted}
        onError={handleError}
        onRefresh={refreshDocuments}
        onSelect={setSelectedDocument}
      />

      <AnalysisPanel
        selectedDocument={selectedDocument}
        onChanged={refreshDashboard}
        onError={handleError}
      />

      <RagPanel selectedDocument={selectedDocument} onError={handleError} />

      <section className="panel-wide">
        <div className="section-heading technical-heading">
          <span className="section-kicker">Operativa local</span>
          <h2>Panel tecnico del MVP</h2>
          <p className="muted">
            Comprobaciones de backend y metricas internas para demostrar que el prototipo esta vivo.
          </p>
        </div>
        <div className="technical-grid">
          <StatusPanel onError={handleError} onStateChange={setBackendState} />
          <AnalyticsPanel analytics={analytics} onError={handleError} onRefresh={refreshAnalytics} />
        </div>
      </section>
    </main>
  );
}
