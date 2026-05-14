import { useState } from "react";
import { checkHealth, checkReady } from "../api/client";

type StatusPanelProps = {
  onError: (message: string) => void;
};

export function StatusPanel({ onError }: StatusPanelProps) {
  const [result, setResult] = useState<unknown>(null);

  async function runCheck(check: "health" | "ready") {
    try {
      const data = check === "health" ? await checkHealth() : await checkReady();
      setResult(data);
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudo comprobar el backend.");
    }
  }

  return (
    <section className="panel">
      <div className="panel-header">
        <h2>Estado Backend</h2>
      </div>
      <div className="actions">
        <button onClick={() => runCheck("health")}>Comprobar health</button>
        <button onClick={() => runCheck("ready")}>Comprobar ready</button>
      </div>
      {result ? <pre>{JSON.stringify(result, null, 2)}</pre> : null}
    </section>
  );
}
