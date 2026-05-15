import { BackendState } from "../App";
import {
  DocumentRecord,
  analyzeDocument,
  checkHealth,
  checkReady,
  getDocumentAnalysis,
  getUsageAnalytics,
  listDocuments,
  uploadDocument
} from "../api/client";
import { createTestPdfFile } from "../utils/createTestPdf";
import { useState } from "react";

type StepStatus = "pendiente" | "ejecutando" | "ok" | "error";

type ValidationStep = {
  key: string;
  label: string;
  status: StepStatus;
  detail?: string;
};

type ValidationPanelProps = {
  onBackendStateChange: (state: BackendState) => void;
  onCompleted: () => void | Promise<void>;
  onDocumentSelected: (document: DocumentRecord) => void;
};

const initialSteps: ValidationStep[] = [
  { key: "health", label: "Health", status: "pendiente" },
  { key: "ready", label: "Ready", status: "pendiente" },
  { key: "pdf", label: "Generar PDF", status: "pendiente" },
  { key: "upload", label: "Subir documento", status: "pendiente" },
  { key: "list", label: "Listar documentos", status: "pendiente" },
  { key: "analyze", label: "Analizar documento", status: "pendiente" },
  { key: "analysis", label: "Consultar analisis", status: "pendiente" },
  { key: "analytics", label: "Analytics", status: "pendiente" }
];

export function ValidationPanel({
  onBackendStateChange,
  onCompleted,
  onDocumentSelected
}: ValidationPanelProps) {
  const [steps, setSteps] = useState<ValidationStep[]>(initialSteps);
  const [result, setResult] = useState<string | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const [payload, setPayload] = useState<unknown>(null);

  function resetSteps() {
    setSteps(initialSteps);
    setPayload(null);
    setResult(null);
  }

  function setStepStatus(key: string, status: StepStatus, detail?: string) {
    setSteps((currentSteps) =>
      currentSteps.map((step) => (step.key === key ? { ...step, status, detail } : step))
    );
  }

  async function runStep<T>(key: string, label: string, action: () => Promise<T>, detail: (data: T) => string) {
    setStepStatus(key, "ejecutando", "Ejecutando...");

    try {
      const data = await action();
      setStepStatus(key, "ok", detail(data));
      return data;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Error desconocido";
      setStepStatus(key, "error", message);
      throw new Error(`La demo fallo en el paso ${label}: ${message}`);
    }
  }

  async function runValidation() {
    resetSteps();
    setIsRunning(true);

    try {
      const health = await runStep("health", "Health", checkHealth, () => "Backend online");
      onBackendStateChange("online");

      const ready = await runStep("ready", "Ready", checkReady, () => "Servicios preparados");

      setStepStatus("pdf", "ejecutando", "Creando factura demo...");
      const file = createTestPdfFile();
      setStepStatus("pdf", "ok", `${file.name} listo para subir`);

      const uploaded = await runStep("upload", "Subir documento", () => uploadDocument(file), (document) => {
        onDocumentSelected(document);
        return `Documento subido correctamente - ID #${document.id}`;
      });

      const documents = await runStep("list", "Listar documentos", listDocuments, (data) => {
        const exists = data.documents.some((document) => document.id === uploaded.id);
        if (!exists) {
          throw new Error("El documento subido no aparece en la lista.");
        }

        return `${data.total} documentos visibles`;
      });

      const analysisRun = await runStep(
        "analyze",
        "Analizar documento",
        () => analyzeDocument(uploaded.id),
        (data) => `${data.analysis.document_type} / riesgo ${data.analysis.risk_level}`
      );

      const analysis = await runStep(
        "analysis",
        "Consultar analisis",
        () => getDocumentAnalysis(uploaded.id),
        (data) => data.summary
      );

      const analytics = await runStep(
        "analytics",
        "Analytics",
        getUsageAnalytics,
        (data) => `${data.documents_processed} procesados`
      );

      setPayload({ health, ready, uploaded, documents, analysisRun, analysis, analytics });
      setResult("Demo completada correctamente. El PDF ya esta convertido en inteligencia documental.");
      await onCompleted();
    } catch (error) {
      onBackendStateChange("offline");
      setResult(error instanceof Error ? error.message : "La demo fallo por un error desconocido.");
    } finally {
      setIsRunning(false);
    }
  }

  return (
    <section className="card panel-wide validation-panel">
      <div className="card-header">
        <div>
          <span className="section-kicker">Demo guiada</span>
          <h2>Demo guiada</h2>
          <p className="muted">
            Genera un PDF de prueba, lo sube al backend, lo analiza y actualiza los resultados
            visibles en la interfaz.
          </p>
        </div>
        <button className="button button-primary" disabled={isRunning} onClick={runValidation}>
          {isRunning ? "Ejecutando demo..." : "Ejecutar demo completa"}
        </button>
      </div>

      <div className="validation-grid">
        {steps.map((step, index) => (
          <div className={`validation-step validation-${step.status}`} key={step.key}>
            <span className="step-index">{String(index + 1).padStart(2, "0")}</span>
            <strong>{step.label}</strong>
            <small>{step.detail ?? step.status}</small>
          </div>
        ))}
      </div>

      {result ? (
        <div className={result.startsWith("Demo completada") ? "alert alert-ok" : "alert alert-error"}>
          {result}
        </div>
      ) : null}

      {payload ? (
        <details className="technical-details">
          <summary>Ver payload tecnico de la prueba</summary>
          <pre className="json-block">{JSON.stringify(payload, null, 2)}</pre>
        </details>
      ) : null}
    </section>
  );
}
