import { useEffect, useState } from "react";
import { DocumentRecord, listDocuments } from "./api/client";
import { AnalysisPanel } from "./components/AnalysisPanel";
import { AnalyticsPanel } from "./components/AnalyticsPanel";
import { DocumentsPanel } from "./components/DocumentsPanel";
import { StatusPanel } from "./components/StatusPanel";
import { UploadPanel } from "./components/UploadPanel";
import { ValidationPanel } from "./components/ValidationPanel";

export default function App() {
  const [documents, setDocuments] = useState<DocumentRecord[]>([]);
  const [selectedDocument, setSelectedDocument] = useState<DocumentRecord | null>(null);
  const [lastUploaded, setLastUploaded] = useState<DocumentRecord | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function refreshDocuments() {
    try {
      const data = await listDocuments();
      setDocuments(data.documents);
      setError(null);
    } catch (refreshError) {
      setError(
        refreshError instanceof Error ? refreshError.message : "No se pudo actualizar la lista."
      );
    }
  }

  function handleUploaded(document: DocumentRecord) {
    setLastUploaded(document);
    setSelectedDocument(document);
    setMessage(`Documento subido: ${document.original_filename}`);
    void refreshDocuments();
  }

  function handleDeleted() {
    setSelectedDocument(null);
    setMessage("Documento eliminado.");
    void refreshDocuments();
  }

  function handleError(errorMessage: string) {
    setError(errorMessage);
    setMessage(null);
  }

  useEffect(() => {
    void refreshDocuments();
  }, []);

  return (
    <main className="app-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">MVP local</p>
          <h1>AI Document Intelligence Hub</h1>
          <p>
            Consola local para probar subida, análisis mock y métricas del backend FastAPI.
          </p>
        </div>
      </header>

      {error ? <div className="alert alert-error">{error}</div> : null}
      {message ? <div className="alert alert-ok">{message}</div> : null}
      {lastUploaded ? (
        <div className="alert alert-ok">Último documento: #{lastUploaded.id}</div>
      ) : null}

      <ValidationPanel onCompleted={refreshDocuments} />

      <div className="dashboard-grid">
        <StatusPanel onError={handleError} />
        <UploadPanel onError={handleError} onUploaded={handleUploaded} />
        <AnalyticsPanel onError={handleError} />
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
        onChanged={refreshDocuments}
        onError={handleError}
      />
    </main>
  );
}
