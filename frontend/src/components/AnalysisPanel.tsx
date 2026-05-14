import { useState } from "react";
import {
  AnalysisRecord,
  DocumentRecord,
  analyzeDocument,
  getDocumentAnalysis,
  reprocessDocument
} from "../api/client";

type AnalysisPanelProps = {
  selectedDocument: DocumentRecord | null;
  onError: (message: string) => void;
  onChanged: () => void;
};

export function AnalysisPanel({ selectedDocument, onError, onChanged }: AnalysisPanelProps) {
  const [result, setResult] = useState<unknown>(null);
  const [isBusy, setIsBusy] = useState(false);
  const busyText = isBusy ? "Analizando documento..." : null;

  async function runAction(action: "analyze" | "get" | "reprocess") {
    if (!selectedDocument) {
      onError("Selecciona un documento antes de analizar.");
      return;
    }

    try {
      setIsBusy(true);
      let data: unknown;
      if (action === "analyze") {
        data = await analyzeDocument(selectedDocument.id);
        onChanged();
      } else if (action === "reprocess") {
        data = await reprocessDocument(selectedDocument.id);
        onChanged();
      } else {
        data = await getDocumentAnalysis(selectedDocument.id);
      }
      setResult(data);
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudo ejecutar el análisis.");
    } finally {
      setIsBusy(false);
    }
  }

  const analysis = result as AnalysisRecord | null;

  return (
    <section className="panel panel-wide">
      <div className="panel-header">
        <h2>Análisis</h2>
      </div>
      {selectedDocument ? (
        <p className="selected-document">
          Documento seleccionado: #{selectedDocument.id} — {selectedDocument.original_filename} —{" "}
          <span className={`status status-${selectedDocument.status}`}>{selectedDocument.status}</span>
        </p>
      ) : (
        <p className="muted">Selecciona un documento para trabajar con su análisis.</p>
      )}
      <div className="actions">
        <button disabled={isBusy} onClick={() => runAction("analyze")}>
          Analizar documento
        </button>
        <button disabled={isBusy} onClick={() => runAction("get")}>
          Ver análisis
        </button>
        <button disabled={isBusy} onClick={() => runAction("reprocess")}>
          Reprocesar
        </button>
      </div>
      {busyText ? <p className="loading-text">{busyText}</p> : null}
      {analysis?.summary ? (
        <div className="analysis-summary">
          <strong>{analysis.document_type}</strong>
          <span>{analysis.risk_level}</span>
          <p>{analysis.summary}</p>
        </div>
      ) : null}
      {result ? <pre>{JSON.stringify(result, null, 2)}</pre> : null}
    </section>
  );
}
