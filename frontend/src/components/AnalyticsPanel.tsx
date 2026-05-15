import { useState } from "react";
import { UsageAnalytics } from "../api/client";

type AnalyticsPanelProps = {
  analytics: UsageAnalytics | null;
  onError: (message: string) => void;
  onRefresh: () => Promise<UsageAnalytics>;
};

const metrics = [
  { key: "documents_uploaded", label: "Subidos" },
  { key: "documents_processed", label: "Procesados" },
  { key: "documents_failed", label: "Fallidos" },
  { key: "total_tokens", label: "Tokens" },
  { key: "estimated_cost", label: "Coste estimado" }
] as const;

export function AnalyticsPanel({ analytics, onError, onRefresh }: AnalyticsPanelProps) {
  const [isLoading, setIsLoading] = useState(false);

  async function handleLoad() {
    try {
      setIsLoading(true);
      await onRefresh();
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudieron cargar las metricas.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <section className="card">
      <div className="card-header compact">
        <div>
          <span className="section-kicker">Uso</span>
          <h2>Analytics</h2>
        </div>
        <button className="button button-secondary" disabled={isLoading} onClick={handleLoad}>
          Actualizar analytics
        </button>
      </div>

      {isLoading ? <p className="loading-text">Cargando metricas...</p> : null}

      <div className="metric-grid">
        {metrics.map((metric) => (
          <div className="metric-card" key={metric.key}>
            <strong>
              {metric.key === "estimated_cost"
                ? `$${Number(analytics?.[metric.key] ?? 0).toFixed(4)}`
                : (analytics?.[metric.key] ?? "--")}
            </strong>
            <span>{metric.label}</span>
          </div>
        ))}
      </div>

      <p className="microcopy">Todavia usando analisis mock, sin coste real de IA.</p>
    </section>
  );
}
