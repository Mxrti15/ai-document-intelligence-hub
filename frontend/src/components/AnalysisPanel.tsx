import { useMemo, useState } from "react";
import {
  AnalysisRecord,
  AnalyzeDocumentResponse,
  DocumentRecord,
  analyzeDocument,
  getDocumentAnalysis,
  reprocessDocument
} from "../api/client";

type JsonObject = Record<string, unknown>;

type AnalysisPanelProps = {
  selectedDocument: DocumentRecord | null;
  onError: (message: string) => void;
  onChanged: () => void;
};

function isAnalyzeResponse(result: unknown): result is AnalyzeDocumentResponse {
  return Boolean(result && typeof result === "object" && "analysis" in result);
}

function getAnalysis(result: unknown): AnalysisRecord | null {
  if (!result || typeof result !== "object") {
    return null;
  }

  if (isAnalyzeResponse(result)) {
    return result.analysis;
  }

  if ("summary" in result && "risk_level" in result) {
    return result as AnalysisRecord;
  }

  return null;
}

function parseJson(value: string) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function isJsonObject(value: unknown): value is JsonObject {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function formatValue(value: unknown) {
  if (value === null || value === undefined || value === "") {
    return "No disponible";
  }

  if (typeof value === "object") {
    return JSON.stringify(value);
  }

  return String(value);
}

function getRecommendedActions(analysis: AnalysisRecord) {
  const actions = [
    "Revisar los datos extraidos antes de enviarlos a sistemas internos.",
    "Guardar el JSON tecnico como evidencia de integracion."
  ];

  if (analysis.risk_level === "high") {
    actions.unshift("Escalar el documento a revision humana por riesgo alto.");
  } else if (analysis.risk_level === "medium") {
    actions.unshift("Validar importes, fechas y condiciones antes de aprobar.");
  } else {
    actions.unshift("Documento apto para automatizacion con control ligero.");
  }

  if (analysis.document_type === "invoice") {
    actions.push("Cruzar proveedor, importe y fecha con el flujo de facturacion.");
  }

  return actions;
}

export function AnalysisPanel({ selectedDocument, onError, onChanged }: AnalysisPanelProps) {
  const [result, setResult] = useState<unknown>(null);
  const [isBusy, setIsBusy] = useState(false);

  const analysis = useMemo(() => getAnalysis(result), [result]);
  const structuredData = analysis ? parseJson(analysis.structured_data_json) : null;
  const tags = analysis ? parseJson(analysis.tags_json) : null;
  const extractedEntries = isJsonObject(structuredData) ? Object.entries(structuredData) : [];
  const recommendedActions = analysis ? getRecommendedActions(analysis) : [];

  async function runAction(action: "analyze" | "get" | "reprocess") {
    if (!selectedDocument) {
      onError("Selecciona un documento de la tabla para analizarlo.");
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
      onError(error instanceof Error ? error.message : "No se pudo ejecutar el analisis.");
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <section className="card panel-wide">
      <div className="card-header">
        <div>
          <span className="section-kicker">Inteligencia documental</span>
          <h2>Resultado de analisis</h2>
        </div>
        {selectedDocument ? (
          <span className={`badge badge-${selectedDocument.status}`}>{selectedDocument.status}</span>
        ) : null}
      </div>

      {selectedDocument ? (
        <div className="selected-document">
          <div>
            <span>Documento seleccionado</span>
            <strong>
              #{selectedDocument.id} - {selectedDocument.original_filename}
            </strong>
          </div>
          <small>{selectedDocument.storage_path}</small>
        </div>
      ) : (
        <div className="empty-state slim">
          <strong>Selecciona un documento para convertirlo en informacion estructurada.</strong>
        </div>
      )}

      <div className="actions">
        <button className="button button-primary" disabled={isBusy || !selectedDocument} onClick={() => runAction("analyze")}>
          Analizar documento
        </button>
        <button className="button button-secondary" disabled={isBusy || !selectedDocument} onClick={() => runAction("get")}>
          Ver analisis
        </button>
        <button className="button button-secondary" disabled={isBusy || !selectedDocument} onClick={() => runAction("reprocess")}>
          Reprocesar
        </button>
      </div>

      {isBusy ? <p className="loading-text">Extrayendo texto, clasificando y generando resumen...</p> : null}

      {analysis ? (
        <div className="intelligence-card">
          <div className="intelligence-header">
            <div>
              <span className="section-kicker">Documento convertido</span>
              <h3>Tarjeta de inteligencia documental</h3>
            </div>
            <span className={`badge badge-risk-${analysis.risk_level}`}>
              Riesgo {analysis.risk_level}
            </span>
          </div>

          <div className="analysis-summary">
            <div className="analysis-card">
              <span>Tipo detectado</span>
              <strong className={`badge badge-type-${analysis.document_type}`}>
                {analysis.document_type}
              </strong>
            </div>
            <div className="analysis-card">
              <span>Riesgo</span>
              <strong className={`badge badge-risk-${analysis.risk_level}`}>
                {analysis.risk_level}
              </strong>
            </div>
            <div className="analysis-card">
              <span>Idioma</span>
              <strong>{analysis.language}</strong>
            </div>
          </div>

          <div className="intelligence-sections">
            <section className="intelligence-section">
              <span>Resumen ejecutivo</span>
              <p>{analysis.summary}</p>
            </section>

            <section className="intelligence-section">
              <span>Datos extraidos</span>
              {extractedEntries.length > 0 ? (
                <dl className="extracted-data">
                  {extractedEntries.map(([key, value]) => (
                    <div key={key}>
                      <dt>{key}</dt>
                      <dd>{formatValue(value)}</dd>
                    </div>
                  ))}
                </dl>
              ) : (
                <p>No hay datos estructurados disponibles para este analisis.</p>
              )}
            </section>

            <section className="intelligence-section">
              <span>Acciones recomendadas</span>
              <ul className="recommended-actions">
                {recommendedActions.map((action) => (
                  <li key={action}>{action}</li>
                ))}
              </ul>
            </section>
          </div>

          <details className="technical-details" open>
            <summary>JSON tecnico</summary>
            <pre className="json-block">
              {JSON.stringify({ result, structured_data: structuredData, tags }, null, 2)}
            </pre>
          </details>
        </div>
      ) : result ? (
        <pre className="json-block">{JSON.stringify(result, null, 2)}</pre>
      ) : null}
    </section>
  );
}
