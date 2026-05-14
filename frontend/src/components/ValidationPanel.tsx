import { useState } from "react";
import {
  analyzeDocument,
  checkHealth,
  checkReady,
  getDocumentAnalysis,
  getUsageAnalytics,
  listDocuments,
  uploadDocument
} from "../api/client";
import { createTestPdfFile } from "../utils/createTestPdf";

type StepStatus = "pendiente" | "ok" | "error";

type ValidationStep = {
  key: string;
  label: string;
  status: StepStatus;
  detail?: string;
};

type ValidationPanelProps = {
  onCompleted: () => void;
};

const initialSteps: ValidationStep[] = [
  { key: "health", label: "Health", status: "pendiente" },
  { key: "ready", label: "Ready", status: "pendiente" },
  { key: "pdf", label: "Generar PDF", status: "pendiente" },
  { key: "upload", label: "Subir documento", status: "pendiente" },
  { key: "list", label: "Listar documentos", status: "pendiente" },
  { key: "analyze", label: "Analizar documento", status: "pendiente" },
  { key: "analysis", label: "Consultar análisis", status: "pendiente" },
  { key: "analytics", label: "Analytics", status: "pendiente" }
];

export function ValidationPanel({ onCompleted }: ValidationPanelProps) {
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

  async function runValidation() {
    resetSteps();
    setIsRunning(true);
    let currentStep = "Health";

    try {
      currentStep = "Health";
      const health = await checkHealth();
      setStepStatus("health", "ok", "Backend disponible");

      currentStep = "Ready";
      const ready = await checkReady();
      setStepStatus("ready", "ok", "Backend listo");

      currentStep = "Generar PDF";
      const file = createTestPdfFile();
      setStepStatus("pdf", "ok", file.name);

      currentStep = "Subir documento";
      const uploaded = await uploadDocument(file);
      setStepStatus("upload", "ok", `Documento #${uploaded.id}`);

      currentStep = "Listar documentos";
      const documents = await listDocuments();
      const exists = documents.documents.some((document) => document.id === uploaded.id);
      if (!exists) {
        throw new Error("El documento subido no aparece en la lista.");
      }
      setStepStatus("list", "ok", `${documents.total} documentos visibles`);

      currentStep = "Analizar documento";
      const analysisRun = await analyzeDocument(uploaded.id);
      setStepStatus(
        "analyze",
        "ok",
        `${analysisRun.analysis.document_type} / ${analysisRun.analysis.risk_level}`
      );

      currentStep = "Consultar análisis";
      const analysis = await getDocumentAnalysis(uploaded.id);
      setStepStatus("analysis", "ok", analysis.summary);

      currentStep = "Analytics";
      const analytics = await getUsageAnalytics();
      setStepStatus("analytics", "ok", `${analytics.documents_processed} procesados`);

      setPayload({ health, ready, uploaded, documents, analysisRun, analysis, analytics });
      setResult("✅ MVP local validado correctamente");
      onCompleted();
    } catch (error) {
      const message = error instanceof Error ? error.message : "Error desconocido";
      const failedStep = initialSteps.find((step) => step.label === currentStep);
      if (failedStep) {
        setStepStatus(failedStep.key, "error", message);
        setResult(`❌ Error en paso ${failedStep.label}: ${message}`);
      } else {
        setResult(`❌ Error: ${message}`);
      }
    } finally {
      setIsRunning(false);
    }
  }

  return (
    <section className="panel panel-wide validation-panel">
      <div className="panel-header">
        <div>
          <h2>Validación MVP local</h2>
          <p className="muted">Ejecuta el flujo completo contra el backend local.</p>
        </div>
        <button disabled={isRunning} onClick={runValidation}>
          {isRunning ? "Validando..." : "Ejecutar prueba completa"}
        </button>
      </div>

      <div className="validation-steps">
        {steps.map((step) => (
          <div className={`validation-step validation-${step.status}`} key={step.key}>
            <span>{step.label}</span>
            <strong>{step.status}</strong>
            {step.detail ? <small>{step.detail}</small> : null}
          </div>
        ))}
      </div>

      {result ? (
        <div className={result.startsWith("✅") ? "alert alert-ok" : "alert alert-error"}>
          {result}
        </div>
      ) : null}

      {payload ? <pre>{JSON.stringify(payload, null, 2)}</pre> : null}
    </section>
  );
}
