import { BackendState } from "../App";
import { checkHealth, checkReady } from "../api/client";
import { useState } from "react";

type StatusPanelProps = {
  onError: (message: string) => void;
  onStateChange: (state: BackendState) => void;
};

export function StatusPanel({ onError, onStateChange }: StatusPanelProps) {
  const [result, setResult] = useState<unknown>(null);
  const [status, setStatus] = useState<BackendState>("pending");
  const [isLoading, setIsLoading] = useState(false);

  async function runCheck(check: "health" | "ready") {
    try {
      setIsLoading(true);
      setStatus("pending");
      const data = check === "health" ? await checkHealth() : await checkReady();
      setResult(data);
      setStatus("online");
      onStateChange("online");
    } catch (error) {
      setStatus("offline");
      onStateChange("offline");
      onError(error instanceof Error ? error.message : "No se pudo comprobar el backend.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <section className="card">
      <div className="card-header compact">
        <div>
          <span className="section-kicker">FastAPI</span>
          <h2>Estado Backend</h2>
        </div>
        <span className={`live-dot live-${status}`}>{status}</span>
      </div>

      <p className="status-copy">
        {status === "online"
          ? "FastAPI responde correctamente."
          : status === "offline"
            ? "El backend no responde ahora mismo."
            : "Pendiente de comprobacion."}
      </p>

      <div className="actions">
        <button className="button button-secondary" disabled={isLoading} onClick={() => runCheck("health")}>
          Comprobar health
        </button>
        <button className="button button-secondary" disabled={isLoading} onClick={() => runCheck("ready")}>
          Comprobar ready
        </button>
      </div>

      {isLoading ? <p className="loading-text">Comprobando backend...</p> : null}
      {result ? <pre className="json-block compact-json">{JSON.stringify(result, null, 2)}</pre> : null}
    </section>
  );
}
